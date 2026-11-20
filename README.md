# Rudy add-on SDK

Write **add-ons** for [Rudy](https://rudy.chat), a Telegram-compatible
messaging server. An add-on is a built-in bot: it runs inside the server,
answers in milliseconds, and never holds a token or a socket. @BotFather on
Rudy is one.

With this SDK you can:

- **write** an add-on as a few pure Elixir functions,
- **test** it locally with a harness that behaves like the server,
- **build** it into a `.rudyaddon` bundle that passes the server's checks, and
- **sign** it for a production server.

```elixir
defmodule Rudy.Addons.Hello do
  use Rudy.Bots.Addon,
    id: 429_900,
    username: "HelloAddonBot",
    capabilities: ~w(messages.reply messages.edit callbacks)

  alias Rudy.Bots.Keyboard

  def handle_update(ctx, %{_: :updateBotCallbackQuery}) do
    count = get(ctx, :count, 0) + 1

    ctx
    |> put(:count, count)
    |> edit_current("Pressed #{count} times.", keyboard: button())
    |> answer_callback("+1")
  end

  def handle_update(ctx, _update) do
    case command(ctx) do
      {"start", _} -> reply(ctx, ["Hello from ", {:bold, "Rudy"}, "!"], keyboard: button())
      _ -> reply(ctx, "Send /start.")
    end
  end

  defp button, do: Keyboard.inline([[{"Press me", "press"}]])
end
```

## How add-ons work

```
 user sends "/start" to @HelloAddonBot
        │
        ▼
 the server stores the message, then calls your handler:
   handle_update(ctx, update) -> ctx with actions (reply, edit, toast, next step)
        │
        ▼
 the server applies the actions and the new conversation state
 in one idempotent storage command: exactly once, even on retries
```

- **Pure handlers.** A handler gets a `Rudy.Bots.Context` and the update, and
  returns the context with *actions*. It does no I/O itself. The server
  applies the actions afterwards, so a retried input never replies twice.
- **Real Telegram updates.** Handlers see the TL updates a bot receives
  (`updateNewMessage`, `updateBotCallbackQuery`, `updateBotInlineQuery`), as
  maps with atom keys.
- **Conversation state.** `step/2`, `put/3`, `get/3` and `finish/1` keep
  per-user state between messages: an Erlang term of at most 16 KB. When you
  change its shape, raise `state_version` and upgrade old state in
  `migrate/2`.
- **Capabilities.** The manifest declares what the add-on may do. The server
  operator approves them, and any action outside them is dropped.
- **Time budgets.** Handlers get 5 s for messages and buttons and 2 s for
  inline queries. For longer work, use `async/3`: it replies "working on it"
  right away and sends the result when done.

## Quick start

```sh
mix archive.install github rudy-chat/addon-sdk   # or add the dependency below
mix rudy.addon.new weather
cd weather
mix deps.get
mix test
mix rudy.addon.build
```

As a dependency in your own project:

```elixir
{:rudy_addon_sdk, github: "rudy-chat/addon-sdk"}
```

An add-on project is `addon.json` plus `lib/**/*.ex`:

```json
{
  "name": "weather",
  "display": "Weather",
  "version": "1.0.0",
  "id": 429950,
  "username": "WeatherBot",
  "module": "Rudy.Addons.Weather",
  "sdk": 1,
  "state_version": 1,
  "capabilities": ["messages.reply", "network.fetch"],
  "hosts": ["api.open-meteo.com"]
}
```

| Field | Meaning |
| :--- | :--- |
| `name` | `a-z`, `0-9`, `_`, 3-32 characters; the add-on's key on the server |
| `version` | `MAJOR.MINOR.PATCH`. Each build gets its own module names, so a server can switch versions with no downtime. |
| `id`, `username` | The add-on's account: an id in 429000-429999 and a username. The operator of the server assigns both. |
| `module` | The main module. It must start with `Rudy.Addons.`; every module under it belongs to the add-on. |
| `sdk` | The SDK version the add-on was written for (1) |
| `state_version` | The version of your conversation-state shape (see `migrate/2`) |
| `capabilities` | What the add-on may do (below) |
| `hosts` | The only hosts `fetch/3` may reach (https) |

## Capabilities

| Capability | Allows |
| :--- | :--- |
| `messages.reply` | `reply/3`, `reply_with/3`: send messages in the conversation |
| `messages.edit` | `edit/4`, `edit_current/3`: edit the add-on's own messages |
| `callbacks` | `answer_callback/3`: the toast or alert after a button press |
| `inline.answer` | `inline_results/3`: answer `@username query` in any chat |
| `jobs` | `async/3`: work outside the time budget |
| `network.fetch` | `fetch/3`: HTTPS GET to the `hosts` the manifest lists (1 MB, 4 s) |

`bots.manage_own` and `addons.manage` are reserved for the server's own
add-ons (@BotFather, the operator bot).

## The SDK

Everything is imported by `use Rudy.Bots.Addon`.

| Function | What it does |
| :--- | :--- |
| `reply(ctx, text, opts)` | Send a message. `text` is a string or rich parts: `"plain"`, `{:bold, s}`, `{:italic, s}`, `{:code, s}`, `{:pre, s}`, `{:link, label, url}`. Options: `keyboard:`, `reply:`, `silent:`. |
| `edit(ctx, id, text, opts)` / `edit_current(ctx, text, opts)` | Edit a message the add-on sent, or the one whose button was pressed |
| `answer_callback(ctx, text, alert: bool)` | The toast after a button press |
| `inline_results(ctx, results, opts)`, `article(id, title, text)` | Inline-mode answers |
| `async(ctx, pending, fun)` | Reply `pending` now and send `fun.()`'s text when it finishes |
| `fetch(ctx, url)` | `{:ok, %{status, body}}` from an approved host |
| `step/2`, `current_step/1`, `put/3`, `get/3`, `finish/1` | Conversation state |
| `text/1`, `command/1`, `callback_data/1`, `callback_message/1`, `photo/1`, `user/1` | Read the update |
| `format(text, values)` | Fill `{name}` holes |
| `link_prefix/1`, `web_app_url/1` | The server's `t.me`-style link prefix, and the URL of the add-on's Mini App |
| `Rudy.Bots.Keyboard.inline/1`, `.reply/2`, `.remove/0` | Keyboards: `{label, data}`, `{label, {:url, url}}`, `{label, {:web_app, url}}`. Telegram limits apply: 100 buttons, 8 per row, data up to 64 bytes. |

Add-on code may call only the SDK, its own modules and a safe part of the
standard library (`Enum`, `Map`, `String`, `Integer`, `Date`, `Regex`,
`URI`, `Rudy.JSON`, ...). Processes, files, ports, `apply` and dynamic code
are refused. `mix rudy.addon.build` checks this at build time, and the
server checks it again at load time.

## Testing

`Rudy.AddonSDK.Harness` runs an add-on the way the server does: state is
stored between inputs (at most 16 KB, `migrate/2` included), ungranted
actions are dropped, and the time budgets are enforced.

```elixir
chat = Harness.start(Rudy.Addons.Hello)
{chat, out} = Harness.send(chat, "/start")
assert [%{text: "Hello from Rudy!"}] = out.replies

{chat, out} = Harness.press(chat, "Press me")
assert [%{text: "Pressed 1 times."}] = out.edits
assert out.toast.message == "+1"

{_chat, out} = Harness.inline(chat, "query")
```

`out` contains `replies`, `edits`, `toast`, `inline`, `refused` (the
capabilities that were missing), `error` (a crash or timeout) and `warnings`.
`Harness.start/2` options let you fake `fetch` responses, grant fewer
capabilities, or start from old state to test `migrate/2`.

## Building, signing, installing

```sh
mix rudy.addon.build                          # _build/NAME-VERSION.rudyaddon
mix rudy.addon.sign --generate                # once: a key pair (keep the .key private)
mix rudy.addon.build --key addon-signing.key  # build and sign
mix rudy.addon.check FILE --public-key HEX    # the server's checks, locally
```

A bundle is a zip with `manifest.json` (your `addon.json` plus the versioned
module name and the sha256 of every beam), the compiled `ebin/*.beam`, and an
Ed25519 `signature` over the manifest.

A Rudy server loads a bundle only if all of these hold:

- the hashes match;
- every import is on the allowlist;
- the `sdk` is not newer than the server's;
- the operator approved the capabilities;
- in production, the signature verifies with one of the keys in its
  `addons: [public_keys: [...]]` configuration.

Build with an Erlang/OTP version no newer than the server's.

## Examples

- [`examples/hello`](examples/hello): commands, rich text, inline and reply
  keyboards, editing in place, toasts.
- [`examples/notes`](examples/notes): a two-step conversation, stored state
  with `migrate/2` from an older shape, a list with per-item buttons, and
  inline search.

## License

[PolyForm Shield 1.0.0](LICENSE.md). You may use this SDK to build, test
and share add-ons, including commercially. You may not use it to make a
product that competes with Rudy.
