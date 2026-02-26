# codex-ios-relay

Open-source Rust relay that lets an iOS app talk to Codex running on your Mac.

## Table of Contents

- [Why this exists](#why-this-exists)
- [Requirements](#requirements)
- [Quick Start (HTTPS, Codex / ChatGPT-backed)](#quick-start-https-codex--chatgpt-backed)
- [Tailscale setup (recommended for iOS)](#tailscale-setup-recommended-for-ios)
- [After setup: fast daily use](#after-setup-fast-daily-use)
- [Trusted certs for iPhone (recommended)](#trusted-certs-for-iphone-recommended)
- [Connect from iOS](#connect-from-ios)
- [Quick API check](#quick-api-check)
- [Provider modes](#provider-modes)
- [Core endpoints](#core-endpoints)
- [iOS request body](#ios-request-body)
- [Common issues](#common-issues)
- [Security notes](#security-notes)
- [Open-source checklist](#open-source-checklist)
- [Config](#config)

## Why this exists

- Continue chats on iOS using your Mac-hosted Codex session.
- Keep auth local on your Mac.
- Use your own account/login (no bundled secrets, no private SDK).


## Future Plans

- iOS XcodeBuild system

## Requirements

- macOS
- Rust (`cargo`)
- Codex CLI installed and logged in (for `provider=codex`)

Check login:

```bash
codex login status
```

## Quick Start (HTTPS, Codex / ChatGPT-backed)

```bash
cd /path/to/Codex_iOS

# optional but strongly recommended
export RELAY_AUTH_TOKEN="$(cargo run --quiet -- new-token)"

cargo run -- serve --provider codex --bind 0.0.0.0:8787
```

HTTPS is enabled by default. The relay auto-generates a self-signed cert/key under `~/.codex-ios-relay/tls/` if you do not pass `--tls-cert/--tls-key` (and includes localhost + detected primary LAN IP in SAN).
If you connect from iPhone/LAN, include your Mac IP as SAN:

```bash
cargo run -- serve --provider codex --bind 0.0.0.0:8787 --tls-san <your-mac-lan-ip>
```

## Tailscale setup (recommended for iOS)

This avoids local network/TLS trust pain on iPhone.

First-time setup on Mac:

```bash
brew install tailscale
sudo brew services start tailscale
sudo tailscale up
```

Then expose relay through tailnet HTTPS:

```bash
tailscale serve --bg https+insecure://127.0.0.1:8787
```

Use the printed `https://<machine>.<tailnet>.ts.net` URL in iOS as your relay URL.
This URL is tailnet-only and resolves only on devices with Tailscale connected.

## After setup: fast daily use

Once everything is configured, daily workflow is just:

```bash
# terminal 1
cargo run -- serve --provider codex --bind 127.0.0.1:8787

# one-time / persistent
tailscale serve --bg https+insecure://127.0.0.1:8787
```

Keep relay running, then open iOS and use the same `https://...ts.net` URL.

## Trusted certs for iPhone (recommended)

For physical iPhone use, prefer a trusted local cert:

```bash
brew install mkcert
mkcert -install
mkcert -cert-file relay-cert.pem -key-file relay-key.pem localhost 127.0.0.1 ::1 <your-mac-lan-ip>

export RELAY_TLS_CERT="$PWD/relay-cert.pem"
export RELAY_TLS_KEY="$PWD/relay-key.pem"
cargo run -- serve --provider codex --bind 0.0.0.0:8787 --tls-cert "$RELAY_TLS_CERT" --tls-key "$RELAY_TLS_KEY"
```

## Connect from iOS

- Preferred: use your Tailscale URL (`https://<machine>.<tailnet>.ts.net`).
- If not using Tailscale, use your Mac LAN URL, not `127.0.0.1`.
- LAN example: `https://192.168.1.20:8787`
- Send `x-relay-token` header if you set `RELAY_AUTH_TOKEN`.
- On physical iPhone, the relay certificate chain must be trusted by iOS (self-signed usually will not be trusted by default).

If you use `127.0.0.1` on iOS, it points to the phone/simulator itself, not your Mac.

## Quick API check

```bash
curl -k https://127.0.0.1:8787/health
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
cargo run -- serve --provider openai --bind 0.0.0.0:8787 --tls-cert "$RELAY_TLS_CERT" --tls-key "$RELAY_TLS_KEY"
```

## Core endpoints

- `GET /health`
- `GET /v1/threads`
- `GET /v1/threads/{thread_id}`
- `POST /v1/chat`

Example chat request:

```bash
curl -k -X POST https://127.0.0.1:8787/v1/chat \
  -H 'content-type: application/json' \
  -H "x-relay-token: $RELAY_AUTH_TOKEN" \
  -d '{"thread_id":null,"message":"Hello from iPhone","model":null}'
```

## iOS request body

```json
{
  "thread_id": "existing-id-or-null",
  "message": "user message",
  "model": null,
  "working_directory": "~/Code/Projects/Codex_iOS"
}
```

Store and reuse `thread_id` on iOS to continue the same conversation.
Set `working_directory` (optional) to run Codex from a specific project directory.

## Common issues

- `Could not connect to the server (-1004)`:
  - relay is not running, or
  - iOS is using `127.0.0.1` instead of your Mac IP, or
  - wrong port/network.
- TLS trust/certificate errors:
  - cert does not include your Mac LAN IP/hostname, or
  - iOS does not trust your local CA/cert chain.
- `OPENAI_API_KEY is required`:
  - you started `provider=openai` without setting key.
  - use `--provider codex` if you want Codex/ChatGPT login flow.
- `tailscale serve` says `failed to connect to local Tailscale daemon`:
  - start daemon with `sudo brew services start tailscale`
  - complete login with `sudo tailscale up`
- `ERR_NAME_NOT_RESOLVED` for `https://<machine>.<tailnet>.ts.net`:
  - confirm device is connected to Tailscale (same account/tailnet)
  - verify tailnet DNS directly:

```bash
dig @100.100.100.100 +short <machine>.<tailnet>.ts.net
```

  - if direct query works but browser still fails on macOS, add split-DNS resolver:

```bash
sudo mkdir -p /etc/resolver
printf "nameserver 100.100.100.100\n" | sudo tee /etc/resolver/<tailnet>.ts.net
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

  - verify with system resolver (preferred on macOS):

```bash
dscacheutil -q host -a name <machine>.<tailnet>.ts.net
curl -I https://<machine>.<tailnet>.ts.net/health
```

  - note: `dig/nslookup` without `@100.100.100.100` may still show public-DNS results and can be misleading for split DNS
  - Chrome/Brave users: disable "Secure DNS" (DoH) for tailnet testing

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
- `RELAY_TLS_CERT` (optional path to PEM cert; enable HTTPS when set with key)
- `RELAY_TLS_KEY` (optional path to PEM private key; enable HTTPS when set with cert)
- `--tls-san` (repeatable CLI flag; add SAN host/IP entries to auto-generated self-signed cert)

Full CLI options:

```bash
cargo run -- serve --help
```
