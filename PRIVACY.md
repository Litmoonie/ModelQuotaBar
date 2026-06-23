# Privacy

ModelQuotaBar is designed as a local-only menu bar utility.

## Local Codex Data

For Codex quota display, the app reads local session log files under:

```text
~/.codex/sessions
```

It looks for `payload.rate_limits` entries and uses those values to display:

- Codex 5-hour quota.
- Codex weekly quota.

The app does not upload Codex logs, prompt text, completion text, or session files. It does not read `~/.codex/auth.json`, and it does not call private OpenAI or Codex APIs.

## DeepSeek Data

DeepSeek balance display is optional.

If you provide a DeepSeek API key, the key is stored in macOS Keychain. The app uses the key only to call:

```text
GET https://api.deepseek.com/user/balance
```

The app displays the returned CNY balance. It does not scrape DeepSeek webpages, track token usage, or estimate spending from local client logs.

The Keychain service name is `io.github.litmoonie.modelquotabar`.

## Network Access

The only network request currently made by the app is the optional DeepSeek balance request described above.

## Data Storage

- Codex quota values are read from existing local logs and kept only in app memory.
- DeepSeek API key is stored in macOS Keychain.
- The app does not create a local database.
- The app does not send analytics.

## Non-Affiliation

ModelQuotaBar is an unofficial project and is not affiliated with OpenAI, Codex, DeepSeek, Anthropic, or any other model provider.
