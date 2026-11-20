# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.Bots.SDK do
  @moduledoc """
  The stable surface add-ons may call (SDK version 1). Every function takes
  and returns a `Rudy.Bots.Context`; nothing here performs I/O. Anything an
  add-on does to the world is an action the runtime applies afterwards, and
  the runtime refuses actions whose capability the operator has not approved.

  On a Rudy server the server's own copy of this module runs; this copy has
  the same functions and the same results, and answers the few calls that
  need the server (`link_prefix/1`, `web_app_url/1`, `fetch/3`, the
  first-party bot management calls) from what the test harness was given
  (see `Rudy.AddonSDK.Harness`).
  """
  alias Rudy.Bots.{Context, Keyboard}

  @version 1
  def version, do: @version

  @doc """
  Sends `text` to the conversation. `text` is a string or a list of parts (see
  `rich/1`: strings, `{:bold, s}`, `{:code, s}`, `{:link, label, url}` ...).
  Options: `:keyboard`, `:reply`, `:silent`, `:entities`.
  """
  def reply(%Context{} = ctx, text, options \\ []) do
    {text, entities} = rich(text)
    options = Map.new(options)
    options = Map.put(options, :entities, entities ++ (options[:entities] || []))
    action(ctx, "messages.reply", {:reply, text, options})
  end

  @doc """
  Edits a message this add-on sent earlier in the conversation: new text (string
  or rich parts) and the inline keyboard in `:keyboard` (none removes it).
  """
  def edit(%Context{} = ctx, message_id, text, options \\ []) when is_integer(message_id) do
    {text, entities} = rich(text)
    options = Map.new(options)
    options = Map.put(options, :entities, entities ++ (options[:entities] || []))
    action(ctx, "messages.edit", {:edit, message_id, text, options})
  end

  @doc "Edits the message whose keyboard was pressed (callback queries only)."
  def edit_current(%Context{} = ctx, text, options \\ []) do
    case callback_message(ctx) do
      nil -> ctx
      id -> edit(ctx, id, text, options)
    end
  end

  @doc """
  Formatted text: a string, or a list of parts. Returns `{text, entities}` with
  entity offsets in UTF-16 units as Telegram counts them. Parts: a string,
  `{:bold, s}`, `{:italic, s}`, `{:code, s}`, `{:pre, s}`, `{:link, label, url}`.
  """
  def rich(text) when is_binary(text), do: {text, []}

  def rich(parts) when is_list(parts) do
    {iodata, entities, _} =
      Enum.reduce(parts, {[], [], 0}, fn part, {out, entities, offset} ->
        {string, entity} = part(part)
        length = utf16(string)

        entities =
          case entity do
            nil -> entities
            kind -> entities ++ [Map.merge(%{offset: offset, length: length}, kind)]
          end

        {[out, string], entities, offset + length}
      end)

    {IO.iodata_to_binary(iodata), entities}
  end

  defp part(string) when is_binary(string), do: {string, nil}
  defp part({:bold, s}), do: {s, %{_: :messageEntityBold}}
  defp part({:italic, s}), do: {s, %{_: :messageEntityItalic}}
  defp part({:code, s}), do: {s, %{_: :messageEntityCode}}
  defp part({:pre, s}), do: {s, %{_: :messageEntityPre, language: ""}}
  defp part({:link, s, url}), do: {s, %{_: :messageEntityTextUrl, url: url}}

  defp utf16(string) do
    case :unicode.characters_to_binary(string, :utf8, :utf16) do
      binary when is_binary(binary) -> div(byte_size(binary), 2)
      _ -> String.length(string)
    end
  end

  @doc "The data of the pressed button (callback queries only)."
  def callback_data(%Context{update: %{_: :updateBotCallbackQuery, data: data}}), do: data
  def callback_data(%Context{}), do: nil

  @doc "The id of the message whose keyboard was pressed (callback queries only)."
  def callback_message(%Context{update: %{_: :updateBotCallbackQuery, msg_id: id}}), do: id
  def callback_message(%Context{}), do: nil

  @doc "The photo the user sent (`%{id, access_hash, file_reference}`), or nil."
  def photo(%Context{
        update: %{message: %{media: %{_: :messageMediaPhoto, photo: %{_: :photo} = photo}}}
      }),
      do: %{id: photo.id, access_hash: photo.access_hash, file_reference: photo.file_reference}

  def photo(%Context{}), do: nil

  @doc "The server's link prefix (`config.me_url_prefix`, ends with `/`)."
  def link_prefix(%Context{runtime: %{link_prefix: prefix}}) when is_binary(prefix),
    do: String.trim_trailing(prefix, "/") <> "/"

  def link_prefix(%Context{}), do: "https://t.me/"

  @doc "The URL of this add-on's Mini App (`web_app` in its manifest), or nil."
  def web_app_url(%Context{runtime: %{web_app_url: url}}), do: url
  def web_app_url(%Context{}), do: nil

  @doc """
  The bots the talking user owns (capability `bots.manage_own`, first-party
  add-ons only): `{bots, total}` with `%{id, username, name}`, `limit` of them
  from `offset`.
  """
  def my_bots(%Context{} = ctx, offset, limit) do
    bots = bots(ctx)
    {bots |> Enum.drop(offset) |> Enum.take(limit), length(bots)}
  end

  @doc "One owned bot as a map, or nil when it is not the user's (first-party add-ons only)."
  def bot_info(%Context{} = ctx, bot_id), do: Enum.find(bots(ctx), &(&1.id == bot_id))

  @doc "An owned bot by `@username` or `username`, or nil (first-party add-ons only)."
  def bot_by_username(%Context{} = ctx, name) do
    wanted = name |> String.trim_leading("@") |> String.downcase()
    Enum.find(bots(ctx), &(String.downcase(&1.username) == wanted))
  end

  defp bots(%Context{runtime: %{bots: bots}}) when is_list(bots), do: bots
  defp bots(%Context{}), do: []

  @doc """
  Acts on a bot the talking user owns (capability `bots.manage_own`). The
  effect runs now, once for this input (an operation derived from the input, the
  position of the call and the effect), before the answer is committed, so its
  result can go into the reply. Returns `{ctx, {:ok, value} | {:error, reason}}`.
  The effects are those of the server's BotFather; the test harness answers them
  with its `:manage` function.
  """
  def manage(%Context{} = ctx, effect) do
    index = ctx.effects
    ctx = %{ctx | effects: index + 1}

    result =
      cond do
        "bots.manage_own" not in ctx.granted -> {:error, :forbidden}
        is_function(ctx.runtime[:manage], 2) -> ctx.runtime.manage.(index, effect)
        true -> {:error, :unavailable}
      end

    {ctx, result}
  end

  @doc "Sends `text` as a reply to the message being handled, with an inline keyboard."
  def reply_with(%Context{} = ctx, text, keyboard) do
    reply(ctx, text, keyboard: keyboard, reply: true)
  end

  @doc "Inline results for an inline query (capability `inline.answer`). See `article/3`."
  def inline_results(%Context{} = ctx, results, options \\ []) do
    action(ctx, "inline.answer", {:inline_results, results, Map.new(options)})
  end

  @doc "An inline article result that sends `text`."
  def article(id, title, text) do
    %{
      _: :inputBotInlineResult,
      id: id,
      type: "article",
      title: title,
      send_message: %{_: :inputBotInlineMessageText, message: text, no_webpage: false}
    }
  end

  @doc "Answers a callback query (a toast, or an alert with `alert: true`)."
  def answer_callback(%Context{} = ctx, text, options \\ []) do
    action(ctx, "callbacks", {:answer_callback, text, Map.new(options)})
  end

  @doc """
  Fetches `url` (GET). Only hosts the manifest lists and the operator approved
  are reachable, and only with the `network.fetch` capability.
  """
  def fetch(%Context{} = ctx, url, options \\ []) when is_binary(url) do
    # The server's rule: https only, exact host in the approved list; the
    # answer is `{:ok, %{status, body}}` (body at most 1 MB, 4 s timeout).
    cond do
      "network.fetch" not in ctx.granted ->
        {:error, :capability_not_granted}

      not allowed_host?(ctx, url) ->
        {:error, :host_not_allowed}

      is_function(ctx.runtime[:fetch], 2) ->
        ctx.runtime.fetch.(url, options)

      true ->
        {:error, :unavailable}
    end
  end

  defp allowed_host?(%Context{hosts: hosts}, url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) -> host in hosts
      _ -> false
    end
  end

  @doc """
  Runs `function` (arity 0, returns the text to send) outside the handler's
  time budget and sends its result when it is done. The user gets `pending`
  right away.
  """
  def async(%Context{} = ctx, pending, function) when is_function(function, 0) do
    ctx |> reply(pending) |> action("jobs", {:job, function})
  end

  @doc "True when the user is one of the server operators (and the add-on may manage add-ons)."
  def operator?(%Context{operator: operator}), do: operator

  @doc "Status of every add-on (only for an operator talking to an add-on with `addons.manage`)."
  def addons(%Context{system: system}), do: Map.get(system, :addons, [])

  @doc """
  Operator commands: `{:pause, name}`, `{:resume, name}`, `{:rollback, name}`,
  `{:approve, name, capability}`. Needs `addons.manage`, and the user must be an operator.
  """
  def manage_addons(%Context{} = ctx, command),
    do: action(ctx, "addons.manage", {:manage, command})

  @doc "Sets the conversation step."
  def step(%Context{} = ctx, step), do: %{ctx | step: step, written: true}

  @doc "Ends the conversation: step and data are cleared."
  def finish(%Context{} = ctx), do: %{ctx | step: nil, data: %{}, written: true}

  def put(%Context{data: data} = ctx, key, value),
    do: %{ctx | data: Map.put(data, key, value), written: true}

  def get(%Context{data: data}, key, default \\ nil), do: Map.get(data, key, default)

  def current_step(%Context{step: step}), do: step
  def user(%Context{user: user}), do: user
  def text(%Context{update: %{message: %{message: text}}}) when is_binary(text), do: text
  def text(%Context{}), do: ""
  def command(ctx), do: ctx |> text() |> Keyboard.command()

  @doc "A text with `{name}` holes filled from `values`."
  def format(text, values) do
    Enum.reduce(values, text, fn {key, value}, acc ->
      String.replace(acc, "{" <> to_string(key) <> "}", to_string(value))
    end)
  end

  defp action(%Context{} = ctx, capability, action) do
    %{ctx | actions: ctx.actions ++ [{capability, action}]}
  end
end
