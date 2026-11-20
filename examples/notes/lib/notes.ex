# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.Addons.Notes do
  @moduledoc """
  @NotesAddonBot: a multi-step conversation with stored state.

    * `/new` asks for a title, then for the text (two steps);
    * `/list` shows the notes with a delete button each;
    * typing `@NotesAddonBot word` in any chat offers matching notes inline;
    * state version 2 keeps notes as maps; `migrate/2` upgrades the version 1
      state (a list of `{title, text}` tuples) the first time a user returns.

  Conversation state is at most 16 KB per user, so this keeps at most 20 notes.
  """
  use Rudy.Bots.Addon,
    id: 429_901,
    username: "NotesAddonBot",
    capabilities: ~w(messages.reply messages.edit callbacks inline.answer),
    state_version: 2

  alias Rudy.Bots.Keyboard
  alias Rudy.Addons.Notes.Store

  @max_notes 20

  def handle_update(ctx, %{_: :updateBotInlineQuery, query: query}) do
    results =
      for {note, index} <- Enum.with_index(Store.search(notes(ctx), query)) do
        article("note#{index}", note.title, note.title <> "\n\n" <> note.text)
      end

    inline_results(ctx, results, cache_time: 0, private: true)
  end

  def handle_update(ctx, %{_: :updateBotCallbackQuery}) do
    case callback_data(ctx) do
      "del:" <> index ->
        # Callback data comes from the client: never trust it to parse.
        title =
          case Integer.parse(index) do
            {i, ""} -> Enum.at(notes(ctx), i, %{title: nil}).title
            _ -> nil
          end

        ctx = put(ctx, :notes, Store.delete(notes(ctx), title))

        ctx
        |> edit_current(list_text(notes(ctx)), keyboard: list_keyboard(notes(ctx)))
        |> answer_callback("Deleted.")

      _ ->
        answer_callback(ctx, "")
    end
  end

  def handle_update(ctx, _update) do
    case command(ctx) do
      {"new", _} ->
        if length(notes(ctx)) >= @max_notes,
          do: reply(ctx, "You have #{@max_notes} notes; delete one first (/list)."),
          else: ctx |> step(:title) |> reply("Title of the note?")

      {"list", _} ->
        reply(ctx, list_text(notes(ctx)), keyboard: list_keyboard(notes(ctx)))

      {"start", _} ->
        reply(ctx, "I keep notes. /new to write one, /list to see them.")

      _ ->
        reply(ctx, "/new or /list")
    end
  end

  def handle_step(ctx, :title, _update) do
    case text(ctx) do
      "/cancel" ->
        ctx |> finish_keeping_notes() |> reply("Cancelled.")

      title when byte_size(title) in 1..64 ->
        ctx |> put(:title, title) |> step(:text) |> reply("And the text?")

      _ ->
        reply(ctx, "A title of 1-64 characters, please (or /cancel).")
    end
  end

  def handle_step(ctx, :text, _update) do
    case text(ctx) do
      "/cancel" ->
        ctx |> finish_keeping_notes() |> reply("Cancelled.")

      text when byte_size(text) in 1..500 ->
        note = %{title: get(ctx, :title), text: text}
        ctx = ctx |> put(:notes, Store.add(notes(ctx), note)) |> finish_keeping_notes()
        reply(ctx, ["Saved ", {:bold, note.title}, "."])

      _ ->
        reply(ctx, "1-500 characters, please (or /cancel).")
    end
  end

  # Version 1 stored notes as {title, text} tuples.
  def migrate(1, %{} = data),
    do:
      Map.update(data, :notes, [], fn list ->
        for {title, text} <- list, do: %{title: title, text: text}
      end)

  def migrate(_from, data), do: data

  # finish/1 clears all data; the notes are kept, the draft is not.
  defp finish_keeping_notes(ctx) do
    kept = notes(ctx)
    ctx |> finish() |> put(:notes, kept)
  end

  defp notes(ctx), do: get(ctx, :notes, [])

  defp list_text([]), do: "No notes yet. /new writes one."
  defp list_text(notes), do: Enum.map_join(notes, "\n", &("• " <> &1.title))

  defp list_keyboard([]), do: nil
  # Callback data is at most 64 bytes, so buttons carry the position, not the title.
  defp list_keyboard(notes),
    do:
      Keyboard.inline(
        for {note, i} <- Enum.with_index(notes), do: [{"Delete " <> note.title, "del:#{i}"}]
      )
end

defmodule Rudy.Addons.Notes.Store do
  @moduledoc "Pure helpers on the list of notes (a second module of the add-on)."

  def add(notes, note), do: Enum.reject(notes, &(&1.title == note.title)) ++ [note]
  def delete(notes, title), do: Enum.reject(notes, &(&1.title == title))

  def search(notes, ""), do: notes

  def search(notes, query) do
    query = String.downcase(query)
    Enum.filter(notes, &String.contains?(String.downcase(&1.title <> " " <> &1.text), query))
  end
end
