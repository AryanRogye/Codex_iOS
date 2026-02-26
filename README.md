# codex-ios-relay

Open-source Rust relay that lets an iOS app talk to Codex running on your Mac.

## Why this exists

- Continue chats on iOS using your Mac-hosted Codex session.
- Keep auth local on your Mac.
- Use your own account/login (no bundled secrets, no private SDK).

## Requirements

- macOS
- Rust (`cargo`)
- Codex CLI installed and logged in (for `provider=codex`)

Check login:

```bash
codex login status
```

## Quick Start (Codex / ChatGPT-backed)

```bash
cd /path/to/Codex_iOS

# optional but strongly recommended
export RELAY_AUTH_TOKEN="$(cargo run --quiet -- new-token)"

cargo run -- serve --provider codex --bind 0.0.0.0:8787
```

That is the main run command most users need.

## Connect from iOS

- Use your Mac LAN URL, not `127.0.0.1`.
- Example: `http://192.168.1.20:8787`
- Send `x-relay-token` header if you set `RELAY_AUTH_TOKEN`.

If you use `127.0.0.1` on iOS, it points to the phone/simulator itself, not your Mac.

## Quick API check

```bash
curl http://127.0.0.1:8787/health
```

Expected:

```json
{"status":"ok","provider":"codex"}
```

## Provider modes

### `codex` (default, recommended)

- Uses local Codex CLI auth (`codex login`), including ChatGPT login.
- No `OPENAI_API_KEY` required.
- `/v1/threads` also reads local Codex history from `~/.codex/sessions`.

### `openai`

- Uses OpenAI Chat Completions directly.
- Requires:

```bash
export OPENAI_API_KEY="<your-key>"
cargo run -- serve --provider openai --bind 0.0.0.0:8787
```

## Core endpoints

- `GET /health`
- `GET /v1/threads`
- `GET /v1/threads/{thread_id}`
- `POST /v1/chat`

Example chat request:

```bash
curl -X POST http://127.0.0.1:8787/v1/chat \
  -H 'content-type: application/json' \
  -H "x-relay-token: $RELAY_AUTH_TOKEN" \
  -d '{"thread_id":null,"message":"Hello from iPhone","model":null}'
```

## iOS request body

```json
{
  "thread_id": "existing-id-or-null",
  "message": "user message",
  "model": null
}
```

Store and reuse `thread_id` on iOS to continue the same conversation.

## Common issues

- `Could not connect to the server (-1004)`:
  - relay is not running, or
  - iOS is using `127.0.0.1` instead of your Mac IP, or
  - wrong port/network.
- `OPENAI_API_KEY is required`:
  - you started `provider=openai` without setting key.
  - use `--provider codex` if you want Codex/ChatGPT login flow.

## Security notes

- Do not expose this publicly without auth.
- Always set `RELAY_AUTH_TOKEN` for non-local use.
- Never commit personal files/secrets:
  - `~/.codex/auth.json`
  - `~/.codex/sessions/*`
  - API keys/tokens

## Open-source checklist

Before pushing publicly:

1. Confirm no secrets are tracked (`.env`, tokens, keys).
2. Confirm iOS signing identity is generic by default (project is set to blank team + `com.example.CodexIOS`).
3. If you distribute an iOS build, set your own bundle identifier and Apple team in Xcode.
4. Keep relay auth enabled when exposing beyond localhost/LAN.

## Config

- `RELAY_PROVIDER` (`codex` or `openai`, default: `codex`)
- `RELAY_CODEX_BIN` (default: `codex`)
- `OPENAI_API_KEY` (required only for `openai`)
- `RELAY_DEFAULT_MODEL` (optional)
- `RELAY_AUTH_TOKEN` (recommended)
- `RELAY_DATA_PATH` (optional)

Full CLI options:

```bash
cargo run -- serve --help
```
