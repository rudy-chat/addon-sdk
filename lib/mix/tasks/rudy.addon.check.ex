# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Mix.Tasks.Rudy.Addon.Check do
  @shortdoc "Checks a bundle the way a Rudy server does before loading it"
  @moduledoc """
      mix rudy.addon.check BUNDLE [--public-key HEX ...]

  Checks the manifest, the file list and hashes, the import allowlist and
  the SDK version; with `--public-key`, also that the signature verifies with
  one of the keys. The one check left to the server is the operator's
  approval of the add-on's capabilities.
  """
  use Mix.Task

  @impl true
  def run(args) do
    {options, rest} = OptionParser.parse!(args, strict: [public_key: :keep])
    Mix.Task.run("compile")
    [file] = rest
    keys = Keyword.get_values(options, :public_key)

    case Rudy.AddonSDK.Bundle.check(File.read!(file), keys) do
      {:ok, bundle} ->
        m = bundle.manifest

        signed =
          cond do
            keys != [] -> "valid"
            bundle.signature -> "present (not verified: pass --public-key)"
            true -> "none (dev servers only)"
          end

        Mix.shell().info(
          "OK #{m["name"]} #{m["version"]}: #{map_size(m["files"])} beams, sdk #{m["sdk"]}, signature #{signed}"
        )

      {:error, reason} ->
        Mix.raise("a server would refuse #{file}: #{inspect(reason)}")
    end
  end
end
