# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.AddonSDK.Harness do
  @moduledoc """
  Runs an add-on the way a Rudy server does, without a server: you send it
  messages, press its buttons and type inline queries, and get back what the
  server would have done.

      chat = Harness.start(Rudy.Addons.Hello)
      {chat, out} = Harness.send(chat, "/start")
      assert [%{text: "Hi! " <> _}] = out.replies
      {chat, out} = Harness.press(chat, "Count")

  What the harness does like the server:

    * the conversation state (`step`, `put/3` data) survives between inputs
      as a stored term of at most 16 KB, and `migrate/2` runs when the state
      was written under an older `state_version`;
    * actions whose capability is not granted are dropped (listed in
      `out.refused`); by default the add-on's own capabilities are granted;
    * handlers get 5 s (messages and buttons) or 2 s (inline queries); a
      crash or timeout is `out.error` and changes nothing;
    * the updates are the TL updates a bot receives (`updateNewMessage`,
      `updateBotCallbackQuery`, `updateBotInlineQuery`), with atom keys.

  What it does not do: automatic entities (commands, links, mentions) the
  server adds to replies, delivery, rate limits.

  Options of `start/2`: `:user` (id, default 1000), `:lang` ("en"),
  `:granted` (list, or `:all`), `:hosts` (approved fetch hosts, default the
  add-on's), `:fetch` (`fn url, options -> {:ok, %{status, body}} end`),
  `:link_prefix`, `:web_app_url`, `:operator` (false), `:system` (map),
  `:state` (`%{step: _, data: _}`) with `:state_version`.
  """
  alias Rudy.Bots.{Context, Conversation}

  defstruct [
    :module,
    :addon,
    :user,
    :lang,
    :granted,
    :hosts,
    :runtime,
    :operator,
    :system,
    state: nil,
    state_version: 1,
    messages: [],
    next_id: 1,
    input: 0
  ]

  @type t :: %__MODULE__{}

  @doc "A conversation between one user and the add-on `module`."
  def start(module, options \\ []) do
    info = module.__addon__()
    capabilities = info.capabilities

    granted =
      case Keyword.get(options, :granted, capabilities) do
        :all ->
          ~w(messages.reply messages.edit callbacks inline.answer jobs network.fetch bots.manage_own addons.manage)

        list ->
          list
      end

    state =
      case Keyword.fetch(options, :state) do
        {:ok, %{} = state} -> :erlang.term_to_binary(Map.merge(%{step: nil, data: %{}}, state))
        :error -> nil
      end

    %__MODULE__{
      module: module,
      addon: info[:id] || 429_999,
      user: Keyword.get(options, :user, 1000),
      lang: Keyword.get(options, :lang, "en"),
      granted: granted,
      hosts: Keyword.get(options, :hosts, info[:hosts] || []),
      operator: Keyword.get(options, :operator, false),
      system: Keyword.get(options, :system, %{}),
      runtime: %{
        link_prefix: Keyword.get(options, :link_prefix, "https://t.me/"),
        web_app_url: Keyword.get(options, :web_app_url),
        fetch: Keyword.get(options, :fetch),
        bots: Keyword.get(options, :bots, []),
        manage: Keyword.get(options, :manage)
      },
      state: state,
      state_version: Keyword.get(options, :state_version, info[:state_version] || 1)
    }
  end

  @doc "The user sends `text` (a command or plain text). Returns `{chat, out}`."
  def send(%__MODULE__{} = chat, text, options \\ []) when is_binary(text) do
    {id, chat} = take_id(chat)

    message = %{
      _: :message,
      id: id,
      out: false,
      message: text,
      date: now(),
      from_id: %{_: :peerUser, user_id: chat.user},
      peer_id: %{_: :peerUser, user_id: chat.addon},
      media: Keyword.get(options, :media),
      entities: [],
      reply_to: nil
    }

    run(chat, :message, %{_: :updateNewMessage, message: message, pts: 0, pts_count: 0})
  end

  @doc "The user sends a photo (with an optional caption)."
  def send_photo(%__MODULE__{} = chat, caption \\ "") do
    photo = %{
      _: :photo,
      id: System.unique_integer([:positive]),
      access_hash: 1,
      file_reference: <<1>>
    }

    send(chat, caption, media: %{_: :messageMediaPhoto, photo: photo})
  end

  @doc """
  The user presses a button: by its label (in the newest message that has
  it), or `{message_id, data}`.
  """
  def press(%__MODULE__{} = chat, label) when is_binary(label) do
    case find_button(chat, label) do
      {id, data} -> press(chat, {id, data})
      nil -> raise ArgumentError, "no inline button #{inspect(label)} in #{inspect(labels(chat))}"
    end
  end

  def press(%__MODULE__{} = chat, {message_id, data}) do
    update = %{
      _: :updateBotCallbackQuery,
      query_id: System.unique_integer([:positive]),
      user_id: chat.user,
      peer: %{_: :peerUser, user_id: chat.user},
      msg_id: message_id,
      chat_instance: 1,
      data: data
    }

    run(chat, :callback, update)
  end

  @doc "The user types `query` after the add-on's username in any chat."
  def inline(%__MODULE__{} = chat, query, offset \\ "") do
    update = %{
      _: :updateBotInlineQuery,
      query_id: System.unique_integer([:positive]),
      user_id: chat.user,
      query: query,
      offset: offset
    }

    run(chat, :inline, update)
  end

  @doc "Every message of the conversation, oldest first: `%{id, from, text, keyboard}`."
  def messages(%__MODULE__{messages: messages}), do: Enum.reverse(messages)

  @doc "The add-on's newest message, or nil."
  def last(%__MODULE__{messages: messages}), do: Enum.find(messages, &(&1.from == :addon))

  @doc "The conversation step the add-on is at."
  def step(%__MODULE__{state: nil}), do: nil
  def step(%__MODULE__{state: state}), do: :erlang.binary_to_term(state).step

  @doc "The conversation data the add-on stored with `put/3`."
  def data(%__MODULE__{state: nil}), do: %{}
  def data(%__MODULE__{state: state}), do: :erlang.binary_to_term(state).data

  # -- running a handler -------------------------------------------------------------

  defp run(chat, kind, update) do
    chat = %{chat | input: chat.input + 1}
    ctx = context(chat, update)

    out = %{
      replies: [],
      edits: [],
      toast: nil,
      inline: nil,
      refused: [],
      error: nil,
      warnings: []
    }

    case invoke(chat.module, ctx, update, if(kind == :inline, do: 2_000, else: 5_000)) do
      {:ok, %Context{} = result} -> apply_result(chat, result, out)
      {:ok, other} -> {chat, %{out | error: {:bad_return, other}}}
      {:error, reason} -> {chat, %{out | error: reason}}
    end
  end

  defp context(chat, update) do
    ctx = %Context{
      addon: chat.addon,
      scope: {:user, chat.user},
      user: chat.user,
      update: update,
      input: <<chat.input::64>>,
      lang: chat.lang,
      capabilities: chat.module.__addon__().capabilities,
      granted: chat.granted,
      hosts: chat.hosts,
      operator: chat.operator,
      system: chat.system,
      runtime: chat.runtime,
      state_version: chat.state_version
    }

    ctx =
      case chat.state do
        nil ->
          ctx

        binary ->
          %{
            ctx
            | step: :erlang.binary_to_term(binary).step,
              data: :erlang.binary_to_term(binary).data
          }
      end

    Conversation.migrate(ctx, chat.module, chat.module.__addon__().state_version)
  end

  defp invoke(module, ctx, update, budget) do
    task =
      Task.async(fn ->
        try do
          case ctx.step do
            nil -> {:ok, module.handle_update(ctx, update)}
            step -> {:ok, module.handle_step(ctx, step, update)}
          end
        rescue
          error -> {:error, {:crashed, Exception.format(:error, error, __STACKTRACE__)}}
        catch
          kind, value -> {:error, {:crashed, {kind, value}}}
        end
      end)

    case Task.yield(task, budget) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  defp apply_result(chat, %Context{} = ctx, out) do
    {allowed, refused} =
      Enum.split_with(ctx.actions, fn {capability, _} -> capability in ctx.granted end)

    out = %{out | refused: Enum.map(refused, &elem(&1, 0))}

    case Conversation.dump(ctx) do
      {:error, reason} ->
        {chat, %{out | error: reason}}

      {:ok, state} ->
        chat =
          case state do
            nil -> chat
            %{schema: schema, data: data} -> %{chat | state: data, state_version: schema}
          end

        Enum.reduce(allowed, {chat, out}, &apply_action/2)
    end
  end

  defp apply_action({_, {:reply, text, options}}, {chat, out}) do
    {id, chat} = take_id(chat)
    keyboard = keyboard(options, out)

    reply = %{
      id: id,
      text: text,
      entities: options[:entities] || [],
      keyboard: elem(keyboard, 0),
      reply: options[:reply] == true,
      silent: options[:silent] == true
    }

    chat = %{
      chat
      | messages: [%{id: id, from: :addon, text: text, keyboard: reply.keyboard} | chat.messages]
    }

    {chat, %{elem(keyboard, 1) | replies: elem(keyboard, 1).replies ++ [reply]}}
  end

  defp apply_action({_, {:edit, id, text, options}}, {chat, out}) do
    {markup, out} = keyboard(options, out)

    case Enum.find(chat.messages, &(&1.id == id and &1.from == :addon)) do
      nil ->
        {chat, %{out | warnings: out.warnings ++ [{:edit_unknown_message, id}]}}

      _ ->
        messages =
          Enum.map(chat.messages, fn
            %{id: ^id} = m -> %{m | text: text, keyboard: markup}
            m -> m
          end)

        {%{chat | messages: messages},
         %{out | edits: out.edits ++ [%{id: id, text: text, keyboard: markup}]}}
    end
  end

  defp apply_action({_, {:answer_callback, text, options}}, {chat, out}),
    do: {chat, %{out | toast: %{message: text, alert: options[:alert] == true}}}

  defp apply_action({_, {:inline_results, results, options}}, {chat, out}),
    do: {chat, %{out | inline: %{results: results, options: options}}}

  defp apply_action({_, {:job, function}}, {chat, out}) do
    case function.() do
      text when is_binary(text) or is_list(text) ->
        {text, entities} = Rudy.Bots.SDK.rich(text)
        apply_action({"jobs", {:reply, text, %{entities: entities}}}, {chat, out})

      other ->
        {chat, %{out | warnings: out.warnings ++ [{:job_returned, other}]}}
    end
  end

  defp apply_action({_, other}, {chat, out}),
    do: {chat, %{out | warnings: out.warnings ++ [{:unapplied, other}]}}

  # A keyboard the server would refuse is dropped: the message goes without one.
  defp keyboard(options, out) do
    case options[:keyboard] do
      nil ->
        {nil, out}

      markup ->
        if Rudy.Bots.Keyboard.valid?(markup),
          do: {markup, out},
          else: {nil, %{out | warnings: out.warnings ++ [{:invalid_keyboard, markup}]}}
    end
  end

  defp take_id(chat), do: {chat.next_id, %{chat | next_id: chat.next_id + 1}}

  defp find_button(chat, label) do
    Enum.find_value(chat.messages, fn
      %{from: :addon, id: id, keyboard: %{_: :replyInlineMarkup, rows: rows}} ->
        Enum.find_value(rows, fn row ->
          Enum.find_value(row.buttons, fn
            %{text: ^label, type: %{_: :inlineButtonTypeCallback, data: data}} -> {id, data}
            _ -> nil
          end)
        end)

      _ ->
        nil
    end)
  end

  defp labels(chat) do
    for %{keyboard: %{_: :replyInlineMarkup, rows: rows}} <- chat.messages,
        row <- rows,
        button <- row.buttons,
        do: button.text
  end

  defp now, do: System.system_time(:second)
end
