# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Mix.Tasks.Rudy.Addon.Sign do
  @shortdoc "Generates a signing key pair, or signs a bundle"
  @moduledoc """
  Ed25519 keys and signatures for bundles.

      mix rudy.addon.sign --generate [--out KEY_FILE]
      mix rudy.addon.sign BUNDLE --key KEY_FILE [--out SIGNED_BUNDLE]

  `--generate` writes the private key to `KEY_FILE` (default
  `addon-signing.key`, mode 600) and prints the public key: the server
  operator puts that one in the server's `addons: [public_keys: [...]]`.
  Keep the private key out of version control.
  """
  use Mix.Task

  @impl true
  def run(args) do
    {options, rest} =
      OptionParser.parse!(args, strict: [generate: :boolean, key: :string, out: :string])

    cond do
      options[:generate] && rest == [] ->
        keys = Rudy.AddonSDK.Signing.generate()
        out = options[:out] || "addon-signing.key"
        if File.exists?(out), do: Mix.raise("#{out} exists; refusing to overwrite a key")
        File.write!(out, keys.private <> "\n")
        File.chmod!(out, 0o600)

        Mix.shell().info(
          "Private key written to #{out}\nPublic key (for the server): #{keys.public}"
        )

      match?([_], rest) ->
        [bundle] = rest
        key = options[:key] || Mix.raise("--key KEY_FILE is required")

        case Rudy.AddonSDK.Signing.sign_bundle(File.read!(bundle), File.read!(key)) do
          {:ok, signed} ->
            out = options[:out] || bundle
            File.write!(out, signed)
            public = Rudy.AddonSDK.Signing.public_key(File.read!(key))
            Mix.shell().info("Signed #{out} (public key #{public})")

          {:error, reason} ->
            Mix.raise("cannot sign #{bundle}: #{inspect(reason)}")
        end

      true ->
        Mix.raise(
          "usage: mix rudy.addon.sign --generate | mix rudy.addon.sign BUNDLE --key KEY_FILE"
        )
    end
  end
end
