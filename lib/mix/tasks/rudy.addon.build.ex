# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Mix.Tasks.Rudy.Addon.Build do
  @shortdoc "Builds the add-on in this project (or DIR) into a .rudyaddon bundle"
  @moduledoc """
  Builds an add-on project into a bundle a Rudy server can load.

      mix rudy.addon.build [DIR] [--out PATH] [--key PRIVATE_KEY_FILE]

  `DIR` holds `addon.json` and `lib/` (default: the current directory). The
  bundle is written to `PATH` (default `_build/NAME-VERSION.rudyaddon`). With
  `--key` it is signed too (see `mix rudy.addon.sign`).
  """
  use Mix.Task

  @impl true
  def run(args) do
    {options, rest} = OptionParser.parse!(args, strict: [out: :string, key: :string])
    Mix.Task.run("compile")
    directory = List.first(rest) || File.cwd!()

    case Rudy.AddonSDK.Builder.build(directory) do
      {:ok, bundle, manifest} ->
        bundle =
          case options[:key] do
            nil -> bundle
            file -> sign!(bundle, file)
          end

        out =
          options[:out] ||
            Path.join("_build", "#{manifest["name"]}-#{manifest["version"]}.rudyaddon")

        File.mkdir_p!(Path.dirname(out))
        File.write!(out, bundle)

        Mix.shell().info("""
        Built #{out}
          add-on       #{manifest["name"]} #{manifest["version"]} (id #{manifest["id"]}, @#{manifest["username"]})
          module       #{manifest["module"]}
          capabilities #{Enum.join(manifest["capabilities"], ", ")}
          beams        #{map_size(manifest["files"])}
          signed       #{if options[:key], do: "yes", else: "no (dev servers only, or sign it with mix rudy.addon.sign)"}
        """)

      {:error, reason} ->
        Mix.raise("build failed: #{inspect(reason)}")
    end
  end

  defp sign!(bundle, file) do
    {:ok, signed} = Rudy.AddonSDK.Signing.sign_bundle(bundle, File.read!(file))
    signed
  end
end
