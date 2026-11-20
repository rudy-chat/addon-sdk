# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.AddonSDK.Allowlist do
  @moduledoc """
  The import allowlist: which external calls the beams of an add-on may make,
  read from the beam's `imports` chunk. This guards against mistakes and is a
  contract for add-on authors; it is not a sandbox against hostile code. The
  operator's signature is the trust boundary.
  """

  @modules ~w(Elixir.Kernel Elixir.Enum Elixir.Map Elixir.List Elixir.String Elixir.Integer
              Elixir.Keyword Elixir.Access Elixir.Base Elixir.Float Elixir.Tuple Elixir.MapSet
              Elixir.Range Elixir.Regex Elixir.Stream Elixir.Bitwise Elixir.URI Elixir.Date
              Elixir.Time Elixir.DateTime Elixir.String.Chars Elixir.Enumerable Elixir.Collectable
              Elixir.List.Chars Elixir.Inspect Elixir.Rudy.Bots.Addon Elixir.Rudy.JSON Elixir.Macro
              Elixir.Rudy.Bots.Keyboard Elixir.Rudy.Bots.Context)a
  @erlang_modules ~w(maps lists binary unicode string re)a

  # `:erlang` carries the operators and type tests every module needs; what it
  # also carries (processes, ports, code loading, dynamic calls) is refused.
  @erlang_forbidden ~w(spawn spawn_link spawn_monitor spawn_opt spawn_request open_port apply
                       halt process_flag register unregister link unlink monitor demonitor send
                       send_after load_nif load_module delete_module purge_module
                       binary_to_term erlang_hibernate trace trace_pattern system_flag
                       set_cookie exit group_leader raise get_stacktrace nif_error)a
  @kernel_forbidden ~w(spawn spawn_link spawn_monitor apply send binding)a

  @doc "Refuses beams that import anything outside the allowlist."
  def check(binary, own_prefix) when is_binary(binary) do
    case :beam_lib.chunks(binary, [:imports]) do
      {:ok, {_module, [imports: imports]}} ->
        case Enum.reject(imports, &allowed?(&1, own_prefix)) do
          [] -> :ok
          bad -> {:error, {:forbidden_imports, Enum.map(bad, &format/1)}}
        end

      _ ->
        {:error, :beam_unreadable}
    end
  end

  # `value.field` on a value the compiler cannot type compiles to this helper.
  defp allowed?({:elixir_erl_pass, :no_parens_remote, 2}, _), do: true
  defp allowed?({:erlang, function, _}, _), do: function not in @erlang_forbidden
  defp allowed?({module, _, _}, _) when module in @erlang_modules, do: true

  defp allowed?({Kernel, function, _}, _), do: function not in @kernel_forbidden

  defp allowed?({module, _, _}, prefix) do
    name = Atom.to_string(module)

    name in Enum.map(@modules, &Atom.to_string/1) or
      sdk?(name) or String.starts_with?(name, "Elixir." <> prefix)
  end

  defp sdk?(name),
    do: name == "Elixir.Rudy.Bots.SDK" or String.starts_with?(name, "Elixir.Rudy.Bots.SDK.")

  defp format({module, function, arity}), do: "#{inspect(module)}.#{function}/#{arity}"
end
