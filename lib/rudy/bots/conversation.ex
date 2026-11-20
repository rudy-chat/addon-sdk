# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.Bots.Conversation do
  @moduledoc """
  Conversation state of one add-on in one scope: a versioned term holding the
  step and the data, at most 16 KB. `migrate/2` of the add-on upgrades state
  written under an older `state_version` on first touch.
  """
  alias Rudy.Bots.Context

  @max 16 * 1024

  def max_size, do: @max

  @doc "Reads the stored row into the context."
  def load(%Context{} = ctx, nil), do: %{ctx | read_version: 0}

  def load(%Context{} = ctx, %{"version" => version, "schema" => schema, "data" => data}) do
    case safe_decode(data) do
      {:ok, %{step: step, data: stored}} ->
        %{ctx | step: step, data: stored, read_version: version, state_version: schema}

      _ ->
        %{ctx | read_version: version}
    end
  end

  @doc "Upgrades state from an older schema through the add-on's `migrate/2`."
  def migrate(%Context{state_version: from} = ctx, module, current) when from != current do
    %{ctx | data: module.migrate(from, ctx.data), state_version: current}
  end

  def migrate(ctx, _, _), do: ctx

  @doc "The state to write, or nil when the handler did not touch it."
  def dump(%Context{written: false}), do: {:ok, nil}

  def dump(%Context{} = ctx) do
    data = :erlang.term_to_binary(%{step: ctx.step, data: ctx.data}, compressed: 6)

    if byte_size(data) <= @max,
      do: {:ok, %{schema: ctx.state_version, data: data}},
      else: {:error, :state_too_big}
  end

  defp safe_decode(data) do
    {:ok, :erlang.binary_to_term(data, [:safe])}
  rescue
    _ -> :error
  end
end
