# Copyright (c) 2026 b00tkitism <b00tkitism@gmail.com>
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Licensed under the PolyForm Shield License 1.0.0; see LICENSE.md.

defmodule Mix.Tasks.Rudy.Addon.New do
  @shortdoc "Creates a new add-on project"
  @moduledoc """
      mix rudy.addon.new NAME [--id ID] [--username USERNAME]

  Creates `NAME/` with `addon.json`, a handler in `lib/`, a test that runs it
  through the harness, and a `mix.exs` depending on this SDK. `NAME` is
  lowercase (`a-z`, `0-9`, `_`, 3-32 characters). The id (429000-429999) and
  the username are given out by the operator of the server the add-on is
  for; the defaults are placeholders.
  """
  use Mix.Task

  @impl true
  def run(args) do
    {options, rest} = OptionParser.parse!(args, strict: [id: :integer, username: :string])
    name = List.first(rest) || Mix.raise("usage: mix rudy.addon.new NAME")

    unless Regex.match?(~r/\A[a-z][a-z0-9_]{2,31}\z/, name),
      do: Mix.raise("NAME must be lowercase a-z, 0-9 or _, 3-32 characters")

    if File.exists?(name), do: Mix.raise("#{name} exists")
    module = Macro.camelize(name)
    id = options[:id] || 429_999
    username = options[:username] || "#{module}Bot"

    files = %{
      "mix.exs" => mix_exs(name, module),
      "addon.json" => addon_json(name, module, id, username),
      "lib/#{name}.ex" => handler(module, id, username),
      "test/#{name}_test.exs" => test(name, module),
      "test/test_helper.exs" => "ExUnit.start()\n",
      ".gitignore" => "/_build/\n/deps/\n*.rudyaddon\n*.key\n",
      ".formatter.exs" => "[inputs: [\"{mix,.formatter}.exs\", \"{lib,test}/**/*.{ex,exs}\"]]\n"
    }

    for {path, content} <- files do
      path = Path.join(name, path)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
      Mix.shell().info("* created #{path}")
    end

    Mix.shell().info("""

    Next:
        cd #{name}
        mix deps.get
        mix test
        mix rudy.addon.build
    """)
  end

  defp mix_exs(name, module) do
    """
    defmodule Rudy.Addons.#{module}.MixProject do
      use Mix.Project

      def project do
        [app: :#{name}, version: "1.0.0", elixir: "~> 1.18", deps: deps()]
      end

      defp deps do
        [{:rudy_addon_sdk, github: "rudy-chat/addon-sdk"}]
      end
    end
    """
  end

  defp addon_json(name, module, id, username) do
    """
    {
      "name": "#{name}",
      "display": "#{module}",
      "version": "1.0.0",
      "id": #{id},
      "username": "#{username}",
      "module": "Rudy.Addons.#{module}",
      "sdk": 1,
      "state_version": 1,
      "capabilities": ["messages.reply", "messages.edit", "callbacks"],
      "hosts": []
    }
    """
  end

  defp handler(module, id, username) do
    """
    defmodule Rudy.Addons.#{module} do
      @moduledoc "@#{username}: says hello and counts button presses."
      use Rudy.Bots.Addon,
        id: #{id},
        username: "#{username}",
        capabilities: ~w(messages.reply messages.edit callbacks),
        state_version: 1

      alias Rudy.Bots.Keyboard

      def handle_update(ctx, %{_: :updateBotCallbackQuery}) do
        count = get(ctx, :count, 0) + 1

        ctx
        |> put(:count, count)
        |> edit_current("Pressed \#{count} times.", keyboard: keyboard())
        |> answer_callback("+1")
      end

      def handle_update(ctx, _update) do
        case command(ctx) do
          {"start", _} -> reply(ctx, ["Hello from ", {:bold, "#{module}"}, "!"], keyboard: keyboard())
          _ -> reply(ctx, "Send /start.")
        end
      end

      defp keyboard, do: Keyboard.inline([[{"Press me", "press"}]])
    end
    """
  end

  defp test(name, module) do
    """
    defmodule Rudy.Addons.#{module}Test do
      use ExUnit.Case
      alias Rudy.AddonSDK.Harness

      test "/start, then the button counts" do
        chat = Harness.start(Rudy.Addons.#{module})
        {chat, out} = Harness.send(chat, "/start")
        assert [%{text: "Hello from #{module}!"}] = out.replies

        {_chat, out} = Harness.press(chat, "Press me")
        assert [%{text: "Pressed 1 times."}] = out.edits
        assert out.toast.message == "+1"
      end

      test "it builds into a bundle a server accepts" do
        assert {:ok, bundle, _} = Rudy.AddonSDK.Builder.build(File.cwd!())
        assert {:ok, _} = Rudy.AddonSDK.Bundle.check(bundle)
      end
    end
    """
    |> String.replace("#{name}", name)
  end
end
