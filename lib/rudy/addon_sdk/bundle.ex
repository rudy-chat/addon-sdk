# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.AddonSDK.Bundle do
  @moduledoc """
  A `*.rudyaddon` bundle: a zip with `manifest.json`, `ebin/*.beam` and an
  optional `signature` (Ed25519 over the manifest bytes exactly as stored).

  The manifest is the project's `addon.json` plus what the build adds:
  `module` (the versioned module name, `Rudy.Addons.Hello.V1_0_0`) and
  `files` (sha256 of every beam). A Rudy server refuses a bundle whose file
  list or hashes do not match, whose beams call outside the import allowlist,
  whose `sdk` is newer than its own, or (in production) whose signature does
  not verify with one of its configured public keys.
  """

  @max_size 8 * 1024 * 1024
  @required ~w(name version id username module sdk capabilities hosts state_version files)

  defstruct [:manifest, :manifest_bytes, :signature, beams: %{}]

  @doc "Packs manifest bytes, beams (`%{\"ebin/x.beam\" => binary}`) and an optional signature."
  def pack(manifest_bytes, beams, signature \\ nil) when is_binary(manifest_bytes) do
    files =
      [{~c"manifest.json", manifest_bytes}] ++
        for({path, bin} <- Enum.sort(beams), do: {String.to_charlist(path), bin}) ++
        if(signature, do: [{~c"signature", signature}], else: [])

    {:ok, {_, zip}} = :zip.create(~c"bundle.rudyaddon", files, [:memory])
    zip
  end

  @doc "Reads a bundle and checks its manifest the way the server does."
  def parse(binary) when is_binary(binary) and byte_size(binary) <= @max_size do
    with {:ok, files} <- unzip(binary),
         {:ok, bytes} <- fetch(files, "manifest.json"),
         {:ok, manifest} <- Rudy.JSON.decode(bytes),
         :ok <- validate(manifest) do
      {:ok,
       %__MODULE__{
         manifest: manifest,
         manifest_bytes: bytes,
         signature: Map.get(Map.new(files), "signature"),
         beams: for({"ebin/" <> _ = path, bin} <- files, into: %{}, do: {path, bin})
       }}
    end
  end

  def parse(_), do: {:error, :bundle_too_big}

  @doc """
  Every check a server makes before loading, except the operator's approval
  of the capabilities: manifest, file list, hashes, imports, and the signature
  when `public_keys` are given.
  """
  def check(binary, public_keys \\ []) do
    with {:ok, bundle} <- parse(binary),
         :ok <- hashes(bundle),
         :ok <- imports(bundle),
         :ok <- sdk(bundle.manifest),
         :ok <- signature(bundle, public_keys) do
      {:ok, bundle}
    end
  end

  @doc "sha256 of a file, lowercase hex, as the manifest lists it."
  def sha(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

  defp unzip(binary) do
    case :zip.unzip(binary, [:memory]) do
      {:ok, files} -> {:ok, for({name, bin} <- files, do: {List.to_string(name), bin})}
      _ -> {:error, :bundle_unreadable}
    end
  end

  defp fetch(files, name) do
    case List.keyfind(files, name, 0) do
      {_, bin} -> {:ok, bin}
      nil -> {:error, {:missing, name}}
    end
  end

  @doc false
  def validate(%{} = manifest) do
    cond do
      Enum.any?(@required, &(not Map.has_key?(manifest, &1))) ->
        {:error, {:manifest_incomplete, Enum.reject(@required, &Map.has_key?(manifest, &1))}}

      not (is_integer(manifest["id"]) and manifest["id"] in 429_000..429_999) ->
        {:error, :bad_addon_id}

      not (is_binary(manifest["name"]) and
               Regex.match?(~r/\A[a-z][a-z0-9_]{2,31}\z/, manifest["name"])) ->
        {:error, :bad_name}

      not (is_binary(manifest["version"]) and
               Regex.match?(~r/\A\d+\.\d+\.\d+\z/, manifest["version"])) ->
        {:error, :bad_version}

      true ->
        :ok
    end
  end

  def validate(_), do: {:error, :manifest_incomplete}

  defp hashes(%__MODULE__{manifest: %{"files" => files}, beams: beams}) do
    cond do
      not is_map(files) or Enum.sort(Map.keys(files)) != Enum.sort(Map.keys(beams)) ->
        {:error, :file_list_mismatch}

      Enum.all?(beams, fn {path, bin} -> sha(bin) == files[path] end) ->
        :ok

      true ->
        {:error, :bad_hash}
    end
  end

  defp imports(%__MODULE__{manifest: manifest, beams: beams}) do
    Enum.reduce_while(beams, :ok, fn {path, bin}, :ok ->
      case Rudy.AddonSDK.Allowlist.check(bin, manifest["module"]) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {path, reason}}}
      end
    end)
  end

  defp sdk(%{"sdk" => wanted}) when is_integer(wanted) do
    if wanted >= 1 and wanted <= Rudy.Bots.SDK.version(),
      do: :ok,
      else: {:error, {:sdk, wanted, Rudy.Bots.SDK.version()}}
  end

  defp sdk(_), do: {:error, :bad_sdk}

  defp signature(_, []), do: :ok

  defp signature(%__MODULE__{signature: nil}, _), do: {:error, :unsigned}

  defp signature(%__MODULE__{signature: sig, manifest_bytes: bytes}, keys) do
    if Enum.any?(keys, &Rudy.AddonSDK.Signing.verify(bytes, sig, &1)),
      do: :ok,
      else: {:error, :bad_signature}
  end
end
