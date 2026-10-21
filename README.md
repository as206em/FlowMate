# FlowMate

A macOS menu bar app that proofreads text with AI. Select text in any app, press a shortcut, and FlowMate fixes typos and grammar using a local Ollama model or OpenAI.

Requires macOS 13 (Ventura) or later.

## Features

- **Proofread anywhere**: select text in any app and press the shortcut (default `⌘.`).
- **Review before replacing**: a results dialog shows the changes. You can edit the result, then **Replace** it in the original app (`⌘↩`), **Copy** it, or **Retry**.
- **Instant replace**: turn off "Show Results Before Replacing" to swap the selected text right away.
- **Proofread Clipboard**: proofread whatever is on the clipboard from the menu bar.
- **Menu bar status**: see the active provider and model, whether the connection works, and whether Accessibility access is missing. Switch provider or model from the menu.
- **Recent results**: re-open recent results from the menu. They're kept in memory only and cleared when FlowMate quits.
- **Ollama and OpenAI**: run fully on your Mac with Ollama, or use OpenAI.
- **Custom instructions**: edit the proofreading instructions, with a reset to the default.
- **Launch at login** and **Light/Dark/System appearance** in Settings → General.
- **API keys in the Keychain**: never written to the config file.

## Using FlowMate

1. Select some text in any app.
2. Press the shortcut (`⌘.` by default; change it in Settings → Proofreading).
3. Review the result and press **Replace** (`⌘↩`), or **Copy**.

The menu bar icon shows what's happening:

| Icon | Meaning |
| --- | --- |
| ✓ circle | Ready |
| Arrows | Proofreading |
| Thumbs up | Done |
| Warning triangle | Failed, nothing selected, or the result was left on the clipboard because you switched apps |
| Plug | The AI provider can't be reached |

## Permissions

FlowMate needs **Accessibility** access to notice the shortcut and to copy and paste in other apps. On first launch macOS asks for it. You can also grant it in **System Settings → Privacy & Security → Accessibility**, or from the FlowMate menu (**Allow Accessibility Access…**). The menu shows a warning until access is granted.

## Installing Ollama

FlowMate uses `gemma3:4b` by default.

```bash
brew install ollama
```

```bash
brew services start ollama
```

```bash
ollama pull gemma3:4b
```

FlowMate connects to `http://127.0.0.1:11434`. Any other installed model can be picked in the menu bar under **Model**.

## Building

1. Install Swift 5.9+ (Xcode or `xcode-select --install`).
2. Create the signing certificate (see below). It only has to be done once.
3. Build the app bundle:

```bash
./build-app.sh
```

This creates `FlowMate.app`, signs it, and opens it. Move it to `/Applications` so **Launch at login** works.

> `build-app.sh` quits any running FlowMate first. It uses `pkill -f FlowMate`, which also matches other processes whose command line contains "FlowMate" (for example an editor opened in this folder).

For development you can also use `swift build`, `swift run` and `swift test`. Launch at login only works from the app bundle.

## Installing on another Mac

The simplest way is to build on that Mac (steps above). The certificate has to be created on each Mac you build on.

If you copy a built `FlowMate.app` from another Mac instead:

- macOS blocks it on first open because it isn't notarized. Open it once, then allow it in **System Settings → Privacy & Security → Open Anyway**.
- The build only runs on the same chip type (Apple Silicon or Intel) as the Mac that built it.
- Grant Accessibility access on the new Mac.

## Signing the app

Signing with the same certificate every time keeps the Accessibility permission and the Keychain access working across rebuilds.

1. Create a self-signed code signing certificate:
   - Open Keychain Access (Applications → Utilities → Keychain Access).
   - From the menu: Keychain Access → Certificate Assistant → Create a Certificate.
   - Fill in:
     - Name: `FlowMate Dev Certificate` (must match the name in `build-app.sh`).
     - Identity Type: Self Signed Root.
     - Certificate Type: Code Signing.
     - Check "Let me override defaults".
   - Accept the defaults until you see Key Usage, and make sure Code Signing is included.
   - Finish. The certificate appears in login → Certificates.
2. Trust the certificate:
   - Double-click the new certificate in Keychain Access.
   - Expand Trust and set Code Signing to Always Trust.
   - Close it and enter your password if prompted.

## Configuration

Settings are stored in `~/Library/Application Support/FlowMate/config.json`:

- Provider URLs (Ollama, OpenAI)
- Proofreading settings (provider, model, instructions, shortcut, dialog preferences)
- App settings (appearance, number of recent results)

The OpenAI API key is stored in the login Keychain (service `com.asem-mkl.FlowMate`), not in the file. Keys found in older config files are moved to the Keychain automatically.

Logs are written to `~/Library/Application Support/FlowMate/logs` and kept for 7 days. They don't contain the text you proofread. Settings → Maintenance can open or clear them, or reset all settings.

## Architecture

- **UI**: SwiftUI views in `Sources/UI/Views/`
- **Services**: AI providers, clipboard, shortcut and Keychain handling in `Sources/Core/Services/`
- **Models**: configuration and status models in `Sources/Models/`
- **App**: app delegate and state in `Sources/App/`

Networking uses Alamofire (Ollama) and URLSession (OpenAI).

## Testing

```bash
swift test
```

Tests use a temporary config file and an in-memory secret store, so they never touch your settings or Keychain.
