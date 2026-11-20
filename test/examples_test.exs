# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

# Defined before the tests: async tests start as soon as their module loads.
defmodule Rudy.Addons.Crash do
  use Rudy.Bots.Addon, id: 429_990, username: "CrashBot", capabilities: ~w(messages.reply)
  def handle_update(_ctx, _update), do: raise("boom")
end

defmodule Rudy.AddonSDK.ExamplesTest do
  use ExUnit.Case, async: true
  alias Rudy.AddonSDK.Harness

  describe "hello" do
    test "/start greets and shows the counter; buttons edit it in place" do
      chat = Harness.start(Rudy.Addons.Hello)
      {chat, out} = Harness.send(chat, "/start")

      assert [
               %{text: "Hi! I am Hello" <> _, entities: [_ | _]},
               %{text: "Counter: 0", keyboard: %{}}
             ] = out.replies

      {chat, out} = Harness.press(chat, "+")
      {chat, _} = Harness.press(chat, "+")
      {chat, out2} = Harness.press(chat, "−")
      assert [%{text: "Counter: 1"}] = out.edits
      assert [%{text: "Counter: 1"}] = out2.edits
      assert out2.toast == %{message: "Count: 1", alert: false}
      assert Harness.data(chat) == %{count: 1}
    end

    test "without the callbacks capability the toast is refused, the edit is not" do
      chat = Harness.start(Rudy.Addons.Hello, granted: ~w(messages.reply messages.edit))
      {chat, _} = Harness.send(chat, "/start")
      {_chat, out} = Harness.press(chat, "+")
      assert out.refused == ["callbacks"]
      assert out.toast == nil
      assert [_] = out.edits
    end
  end

  describe "notes" do
    test "a two-step conversation, a list with buttons and inline search" do
      chat = Harness.start(Rudy.Addons.Notes)
      {chat, out} = Harness.send(chat, "/new")
      assert [%{text: "Title of the note?"}] = out.replies
      assert Harness.step(chat) == :title

      {chat, _} = Harness.send(chat, "Shopping")
      assert Harness.step(chat) == :text
      {chat, out} = Harness.send(chat, "milk, bread")
      assert [%{text: "Saved Shopping."}] = out.replies
      assert Harness.step(chat) == nil
      assert Harness.data(chat) == %{notes: [%{title: "Shopping", text: "milk, bread"}]}

      {_chat, out} = Harness.inline(chat, "bread")
      assert [%{title: "Shopping"}] = out.inline.results

      {chat, out} = Harness.send(chat, "/list")
      assert [%{text: "• Shopping"}] = out.replies
      {_chat, out} = Harness.press(chat, "Delete Shopping")
      assert [%{text: "No notes yet." <> _}] = out.edits
    end

    test "callback data from the client is never trusted" do
      chat = Harness.start(Rudy.Addons.Notes)
      {chat, _} = Harness.send(chat, "/list")
      {_chat, out} = Harness.press(chat, {1, "del:not-a-number"})
      assert out.error == nil
    end

    test "state written by version 1 is migrated on first touch" do
      chat =
        Harness.start(Rudy.Addons.Notes,
          state: %{data: %{notes: [{"Old", "kept"}]}},
          state_version: 1
        )

      {chat, out} = Harness.send(chat, "/list")
      assert [%{text: "• Old"}] = out.replies
      {_chat, out} = Harness.inline(chat, "kept")
      assert [%{title: "Old"}] = out.inline.results
    end
  end

  test "a crash changes nothing and is reported" do
    {_chat, out} = Harness.send(Harness.start(Rudy.Addons.Crash), "hi")
    assert {:crashed, text} = out.error
    assert text =~ "boom"
    assert out.replies == []
  end
end
