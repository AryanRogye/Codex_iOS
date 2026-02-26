# Contributing

Thanks for contributing.

## Local setup

1. Install Rust and Xcode.
2. Install Codex CLI and log in (`codex login`).
3. Run checks:

```bash
cargo fmt --all
cargo check
```

4. Optional iOS simulator build:

```bash
xcodebuild \
  -project Codex_iOS/Codex_iOS.xcodeproj \
  -scheme Codex_iOS \
  -destination 'generic/platform=iOS Simulator' \
  build
```

## Pull request expectations

1. Keep changes focused and documented.
2. Include reproduction steps for bug fixes.
3. Update `README.md` when behavior or flags change.
4. Do not commit secrets or personal local data.
5. Any new or changed networking functionality must include automated tests (unit/integration) that cover success and failure paths.

## Security and privacy

- Never commit API keys or relay tokens.
- Never commit `~/.codex/auth.json` or `~/.codex/sessions/*`.
