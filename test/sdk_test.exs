# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Rudy.Bots.SDKTest do
  use ExUnit.Case, async: true
  alias Rudy.Bots.{Context, Keyboard, SDK}

  test "rich text counts entity offsets in UTF-16 units, as Telegram does" do
    assert {"😀 bold", [%{offset: 3, length: 4, _: :messageEntityBold}]} =
             SDK.rich(["😀 ", {:bold, "bold"}])

    assert {"a link", [%{_: :messageEntityTextUrl, url: "https://x.y", offset: 2, length: 4}]} =
             SDK.rich(["a ", {:link, "link", "https://x.y"}])
  end

  test "commands drop a @bot suffix" do
    assert Keyboard.command("/start@HelloBot payload") == {"start", "payload"}
    assert Keyboard.command("hello") == nil
  end

  test "keyboards follow Telegram's limits" do
    assert Keyboard.valid?(Keyboard.inline([[{"a", "1"}]]))
    refute Keyboard.valid?(Keyboard.inline([[{"a", String.duplicate("x", 65)}]]))
    refute Keyboard.valid?(Keyboard.inline([for(i <- 1..9, do: {"#{i}", "#{i}"})]))
  end

  test "actions are collected, not performed" do
    ctx = %Context{} |> SDK.reply("hi") |> SDK.answer_callback("ok", alert: true)

    assert [
             {"messages.reply", {:reply, "hi", _}},
             {"callbacks", {:answer_callback, "ok", %{alert: true}}}
           ] = ctx.actions
  end

  test "fetch follows the server's rules" do
    ctx = %Context{
      granted: ["network.fetch"],
      hosts: ["api.example.com"],
      runtime: %{fetch: fn _, _ -> {:ok, %{status: 200, body: "{}"}} end}
    }

    assert {:ok, %{status: 200}} = SDK.fetch(ctx, "https://api.example.com/x")
    assert {:error, :host_not_allowed} = SDK.fetch(ctx, "http://api.example.com/x")
    assert {:error, :host_not_allowed} = SDK.fetch(ctx, "https://other.example.com/x")

    assert {:error, :capability_not_granted} =
             SDK.fetch(%{ctx | granted: []}, "https://api.example.com/x")
  end

  test "Rudy.JSON keeps the server's contract" do
    assert {:ok, %{"a" => [1, 2]}} = Rudy.JSON.decode(~s({"a":[1,2]}))
    assert {:error, :invalid_json} = Rudy.JSON.decode("{")
    assert is_binary(Rudy.JSON.encode(%{"a" => 1}))
  end
end
