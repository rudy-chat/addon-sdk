# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.AddonSDK.Signing do
  @moduledoc """
  Ed25519 signing of bundles, as Rudy servers verify them. The server
  operator generates a key pair once (`mix rudy.addon.sign --generate`); the
  public key (hex) goes in the server's `addons: [public_keys: [...]]`
  configuration and the private key stays with the operator. A server only
  loads bundles signed by one of its keys (a development server can be set to
  accept unsigned ones).
  """

  @doc "A new key pair, lowercase hex: `%{public: ..., private: ...}`."
  def generate do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    %{public: Base.encode16(public, case: :lower), private: Base.encode16(private, case: :lower)}
  end

  @doc "The signature of `manifest_bytes` with a hex private key."
  def sign(manifest_bytes, private_hex),
    do: :crypto.sign(:eddsa, :none, manifest_bytes, [decode(private_hex), :ed25519])

  @doc "True when `signature` is a valid signature of `manifest_bytes` for the hex public key."
  def verify(manifest_bytes, signature, public_hex) when is_binary(signature) do
    :crypto.verify(:eddsa, :none, manifest_bytes, signature, [decode(public_hex), :ed25519])
  rescue
    _ -> false
  end

  def verify(_, _, _), do: false

  @doc "Signs a bundle: the same bundle with a `signature` file."
  def sign_bundle(binary, private_hex) do
    with {:ok, bundle} <- Rudy.AddonSDK.Bundle.parse(binary) do
      signature = sign(bundle.manifest_bytes, private_hex)
      {:ok, Rudy.AddonSDK.Bundle.pack(bundle.manifest_bytes, bundle.beams, signature)}
    end
  end

  @doc "The public key (hex) of a hex private key."
  def public_key(private_hex) do
    {public, _} = :crypto.generate_key(:eddsa, :ed25519, decode(private_hex))
    Base.encode16(public, case: :lower)
  end

  defp decode(hex), do: Base.decode16!(String.trim(hex), case: :mixed)
end
