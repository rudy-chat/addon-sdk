# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.Bots.Keyboard do
  @moduledoc "Inline keyboards for add-on replies, as the TL reply markup a message stores."

  @doc "Rows of `{label, callback_data}`, `{label, {:url, url}}` and `{label, {:web_app, url}}` buttons."
  def inline(rows) do
    %{
      _: :replyInlineMarkup,
      rows:
        for row <- rows do
          %{
            _: :keyboardInlineButtonRow,
            buttons:
              for button <- row do
                case button do
                  {label, {:web_app, url}} ->
                    %{
                      _: :keyboardInlineButton,
                      text: label,
                      type: %{_: :inlineButtonTypeWebView, url: url}
                    }

                  {label, {:url, url}} ->
                    %{
                      _: :keyboardInlineButton,
                      text: label,
                      type: %{_: :inlineButtonTypeUrl, url: url}
                    }

                  {label, data} ->
                    %{
                      _: :keyboardInlineButton,
                      text: label,
                      type: %{_: :inlineButtonTypeCallback, data: data}
                    }
                end
              end
          }
        end
    }
  end

  @doc """
  A reply keyboard: `rows` is a list of lists of labels. Options: `:resize`
  (default true), `:one_time` (default true, the keyboard hides after a tap),
  `:placeholder`.
  """
  def reply(rows, options \\ []) do
    %{
      _: :replyKeyboardMarkup,
      resize: Keyword.get(options, :resize, true),
      single_use: Keyword.get(options, :one_time, true),
      placeholder: Keyword.get(options, :placeholder),
      rows:
        for row <- rows do
          %{
            _: :keyboardButtonRow,
            buttons:
              for(
                label <- row,
                do: %{_: :keyboardButton, text: label, type: %{_: :buttonTypeDefault}}
              )
          }
        end
    }
  end

  @doc "Removes the reply keyboard the user sees."
  def remove, do: %{_: :replyKeyboardHide}

  @doc "`{\"/cmd\", \"rest\"}` of a command text, or nil. A `@bot` suffix is dropped."
  def command("/" <> rest) do
    [head | tail] = String.split(rest, " ", parts: 2)
    [name | _] = String.split(head, "@", parts: 2)
    {name, tail |> List.first() |> Kernel.||("")}
  end

  def command(_), do: nil

  @doc "Telegram limits: 100 buttons, 8 per row, callback data up to 64 bytes."
  def valid?(%{_: :replyKeyboardHide}), do: true

  def valid?(%{rows: rows}) do
    buttons = Enum.flat_map(rows, & &1.buttons)

    length(buttons) <= 100 and Enum.all?(rows, &(length(&1.buttons) <= 8)) and
      Enum.all?(buttons, &(byte_size(data(&1)) <= 64 and byte_size(&1[:text] || "") > 0))
  end

  def valid?(_), do: false

  defp data(%{type: %{data: data}}) when is_binary(data), do: data
  defp data(%{data: data}) when is_binary(data), do: data
  defp data(_), do: ""
end
