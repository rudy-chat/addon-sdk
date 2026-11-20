# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.AddonSDK.MixProject do
  use Mix.Project

  @version "1.0.0"

  def project do
    [
      app: :rudy_addon_sdk,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: [],
      description: "Write, test, build and sign add-ons (built-in bots) for Rudy servers.",
      docs: [main: "readme", extras: ["README.md", "CHANGELOG.md"]]
    ]
  end

  def application, do: [extra_applications: [:crypto]]

  # The examples are compiled in tests, so their tests can call them.
  defp elixirc_paths(:test), do: ["lib", "examples/hello/lib", "examples/notes/lib"]
  defp elixirc_paths(_), do: ["lib"]
end
