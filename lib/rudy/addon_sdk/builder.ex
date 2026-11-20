# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.AddonSDK.Builder do
  @moduledoc """
  Builds an add-on project (`addon.json` and `lib/**/*.ex`) into a bundle,
  the way a Rudy server's own build does:

    * every module under the manifest's `module` (`Rudy.Addons.Hello.*`) is
      renamed to the versioned name (`Rudy.Addons.Hello.V1_0_0.*`) before it
      is compiled, so a server can run two versions side by side while it
      switches;
    * the manifest gets the versioned `module` and the sha256 of every beam;
    * every beam is checked against the import allowlist, so a bundle the
      server would refuse never gets built.

  The project is compiled against this SDK (`use Rudy.Bots.Addon`, the
  `Rudy.Bots.SDK` functions). Build with an Erlang/OTP no newer than the
  server's: a server cannot load beams from a newer compiler.
  """
  alias Rudy.AddonSDK.{Allowlist, Bundle}

  @doc "Returns `{:ok, bundle_binary, manifest}` or `{:error, reason}`."
  def build(directory) do
    with {:ok, spec} <- spec(directory),
         :ok <- Bundle.validate(Map.merge(spec, %{"files" => %{}})),
         {:ok, beams} <- compile_all(directory, spec) do
      manifest =
        spec
        |> Map.put("module", versioned_name(spec))
        |> Map.put("files", Map.new(beams, fn {path, bin} -> {path, Bundle.sha(bin)} end))

      bytes = Rudy.JSON.encode(manifest)
      {:ok, Bundle.pack(bytes, beams), manifest}
    end
  end

  @doc "The versioned module name a build gives this manifest."
  def versioned_name(%{"module" => module, "version" => version}),
    do: module <> ".V" <> String.replace(version, ".", "_")

  defp spec(directory) do
    with {:ok, text} <- File.read(Path.join(directory, "addon.json")),
         {:ok, %{} = spec} <- Rudy.JSON.decode(text) do
      spec =
        Map.merge(%{"capabilities" => [], "hosts" => [], "state_version" => 1, "sdk" => 1}, spec)

      if is_binary(spec["module"]) and String.starts_with?(spec["module"], "Rudy.Addons."),
        do: {:ok, Map.delete(spec, "files")},
        else: {:error, :module_must_start_with_rudy_addons}
    else
      _ -> {:error, :addon_json_unreadable}
    end
  end

  defp compile_all(directory, spec) do
    base = String.split(spec["module"], ".")
    versioned = String.split(versioned_name(spec), ".")
    files = Enum.sort(Path.wildcard(Path.join(directory, "lib/**/*.ex")))

    beams =
      for file <- files, {module, binary} <- compile(file, base, versioned), into: %{} do
        {"ebin/#{module}.beam", binary}
      end

    cond do
      beams == %{} ->
        {:error, :nothing_to_build}

      not Map.has_key?(beams, "ebin/Elixir.#{versioned_name(spec)}.beam") ->
        {:error, {:main_module_missing, spec["module"]}}

      true ->
        case Enum.find_value(beams, &refused(&1, versioned_name(spec))) do
          nil -> {:ok, beams}
          error -> error
        end
    end
  end

  defp refused({path, binary}, prefix) do
    case Allowlist.check(binary, prefix) do
      :ok -> nil
      {:error, reason} -> {:error, {path, reason}}
    end
  end

  defp compile(file, base, versioned) do
    quoted =
      file
      |> File.read!()
      |> Code.string_to_quoted!(file: file)
      |> Macro.prewalk(&rename(&1, base, versioned))

    previous = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      modules = Code.compile_quoted(quoted, file)
      # The versioned modules were only compiled to be packed; unload them.
      for {module, _} <- modules, do: :code.purge(module) && :code.delete(module)
      for {module, binary} <- modules, do: {Atom.to_string(module), binary}
    after
      Code.put_compiler_option(:ignore_module_conflict, previous)
    end
  end

  defp rename({:__aliases__, meta, parts}, base, versioned) do
    names = Enum.map(parts, &to_string/1)

    if Enum.take(names, length(base)) == base,
      do:
        {:__aliases__, meta,
         Enum.map(versioned, &String.to_atom/1) ++ Enum.drop(parts, length(base))},
      else: {:__aliases__, meta, parts}
  end

  defp rename(other, _, _), do: other
end
