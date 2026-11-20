# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.Bots.Addon do
  @moduledoc """
  The behaviour of a built-in bot. An add-on is a set of pure functions:

      def handle_update(ctx, update), do: ctx |> reply("hi")
      def handle_step(ctx, step, update), do: ctx
      def migrate(from_state_version, state), do: state

  `ctx` is a `Rudy.Bots.Context`; the functions only call `Rudy.Bots.SDK`
  and return the context with actions. The runtime applies the actions in one
  idempotent storage command. Options of `use`: `:id` (429000-429999),
  `:username`, `:name`, `:capabilities`, `:state_version`, `:sdk` (the SDK
  version it was written for).
  """
  @callback handle_update(Rudy.Bots.Context.t(), map()) :: Rudy.Bots.Context.t()
  @callback handle_step(Rudy.Bots.Context.t(), term(), map()) :: Rudy.Bots.Context.t()
  @callback migrate(non_neg_integer(), map()) :: map()

  defmacro __using__(options) do
    quote do
      @behaviour Rudy.Bots.Addon
      import Rudy.Bots.SDK
      @rudy_addon unquote(options)

      @doc false
      def __addon__ do
        defaults = %{capabilities: [], state_version: 1, sdk: 1, hosts: []}
        Map.merge(defaults, Map.new(@rudy_addon))
      end

      def handle_step(ctx, _step, _update), do: ctx
      def migrate(_from, state), do: state
      defoverridable handle_step: 3, migrate: 2
    end
  end
end
