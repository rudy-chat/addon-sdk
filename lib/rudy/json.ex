# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.JSON do
  @moduledoc """
  JSON for add-ons (on the import allowlist). Same contract as the server's
  module: `encode/1` returns a binary, `decode/1` returns `{:ok, value}` or
  `{:error, :invalid_json}` and refuses inputs over 1 MB.
  """

  @max 1_048_576

  def encode(value), do: JSON.encode!(value)

  def decode(binary) when is_binary(binary) and byte_size(binary) <= @max do
    case JSON.decode(binary) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  def decode(_), do: {:error, :invalid_json}
end
