# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.Addons.Hello do
  @moduledoc """
  @HelloAddonBot: the smallest useful add-on. `/start` greets with formatted
  text and an inline keyboard; the buttons edit that message in place and
  answer with a toast; anything else gets a reply keyboard.
  """
  use Rudy.Bots.Addon,
    id: 429_900,
    username: "HelloAddonBot",
    capabilities: ~w(messages.reply messages.edit callbacks),
    state_version: 1

  alias Rudy.Bots.Keyboard

  def handle_update(ctx, %{_: :updateBotCallbackQuery}) do
    count = get(ctx, :count, 0)

    count =
      case callback_data(ctx) do
        "plus" -> count + 1
        "minus" -> max(count - 1, 0)
        "reset" -> 0
        _ -> count
      end

    ctx
    |> put(:count, count)
    |> edit_current(counter(count), keyboard: buttons())
    |> answer_callback("Count: #{count}")
  end

  def handle_update(ctx, _update) do
    case command(ctx) do
      {"start", _} ->
        ctx
        |> reply([
          "Hi! I am ",
          {:bold, "Hello"},
          ", an add-on built with the ",
          {:link, "Rudy add-on SDK", "https://github.com/rudy-chat/addon-sdk"},
          "."
        ])
        |> reply(counter(get(ctx, :count, 0)), keyboard: buttons())

      {"help", _} ->
        reply(ctx, "/start - the counter\n/help - this text")

      _ ->
        reply(ctx, "Try /start.", keyboard: Keyboard.reply([["/start", "/help"]]))
    end
  end

  defp counter(count), do: ["Counter: ", {:code, Integer.to_string(count)}]

  defp buttons, do: Keyboard.inline([[{"−", "minus"}, {"+", "plus"}], [{"Reset", "reset"}]])
end
