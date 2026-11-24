# ModelQuotaBar

A local macOS menu bar monitor for AI model quotas and account balances.

ModelQuotaBar currently shows:

```text
Codex 99%
```

The menu contains secondary account details:

```text
Codex weekly 99%
DS balance ¥32.15
Refresh
Quit
```

This is an unofficial tool. It is not affiliated with OpenAI, Codex, DeepSeek, Anthropic, or any other model provider.

## Features

- Reads Codex quota data from local Codex session logs under `~/.codex/sessions`.
- Shows Codex 5-hour quota in the macOS menu bar.
- Shows Codex weekly quota in the menu.
- Optionally shows Claude subscription quota alongside Codex.
- Optionally reads DeepSeek account balance through the official `/user/balance` API.
- Stores the DeepSeek API key in macOS Keychain.
- Does not upload local Codex logs or prompt content.

## Requirements

- macOS 13 or newer.
- Swift 6 toolchain.
- Local Codex session logs at `~/.codex/sessions` for Codex quota display.
- Optional DeepSeek API key for DeepSeek balance display.

## Build

```bash
git clone https://github.com/Litmoonie/ModelQuotaBar.git
cd ModelQuotaBar
Scripts/package-app.sh
```

The packaged app is created at:

```text
dist/ModelQuotaBar.app
```

Run it with:

```bash
open dist/ModelQuotaBar.app
```

The package script uses ad-hoc signing. This is enough for local builds, but downloaded builds may still be blocked by macOS Gatekeeper unless they are Developer ID signed and notarized.

For a stable signing identity across rebuilds, package with the same
Apple or local code-signing certificate each time:

```bash
MODELQUOTABAR_SIGNING_IDENTITY="Apple Development: Your Name" Scripts/package-app.sh
```

## Claude Setup

With Claude Code signed in to an eligible Claude subscription, add the
following `statusLine` entry to your existing `~/.claude/settings.json`.
Replace the example path with the absolute path to your packaged app.

```json
{
  "statusLine": {
    "type": "command",
    "command": "'/absolute/path/to/ModelQuotaBar.app/Contents/MacOS/ModelQuotaBar' --capture-claude-quota"
  }
}
```

If you already have a status line, keep it and have its script forward the
same stdin JSON to the command above as well. The capture command is silent.

After Claude Code receives an API response, the menu bar can show
`CX 72 · CC 58` (both 5-hour remaining percentages). The menu uses full names
and includes weekly percentages. A missing or expired window shows `--`.
The app reads the latest local snapshot every 10 seconds, and Claude Code
supplies updates during status-line runs. See the
[Claude Code status-line documentation](https://code.claude.com/docs/en/statusline#rate-limit-usage).

To disable the integration, remove the capture command from your status line and
delete `~/Library/Application Support/ModelQuotaBar/claude-quota.json`.

## DeepSeek Setup

If the menu shows:

```text
DS balance Set API Key
```

click that row and enter a DeepSeek API key. The key is stored in macOS Keychain under this app's service name.

DeepSeek balance is fetched from:

```text
GET https://api.deepseek.com/user/balance
```

The app only displays CNY balance. It does not track DeepSeek usage or scrape the DeepSeek usage webpage.

## Debug

Print the latest local Codex quota snapshot:

```bash
dist/ModelQuotaBar.app/Contents/MacOS/ModelQuotaBar --print-snapshot
```

Run built-in self checks:

```bash
dist/ModelQuotaBar.app/Contents/MacOS/ModelQuotaBar --self-test
```

## Limitations

- Codex quota data comes from local session logs, not a public Codex quota API.
- If Codex updates quota server-side before writing a new local `rate_limits` event, ModelQuotaBar may temporarily lag behind the official Codex app.
- If Codex changes its local log format, the parser may need an update.
- DeepSeek balance requires a valid API key and network access to DeepSeek's official API.
- No prebuilt notarized app is currently provided.

## Privacy

See [PRIVACY.md](PRIVACY.md).

## License

MIT. See [LICENSE](LICENSE).
