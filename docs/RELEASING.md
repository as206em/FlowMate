# Releasing FlowMate

Builds run on GitHub Actions. Installed copies update themselves with [Sparkle 2](https://sparkle-project.org).

| Workflow | When | What it does |
|---|---|---|
| `ci.yml` | every push and pull request | tests, universal build, signs (Developer ID when the secrets exist, ad-hoc otherwise), uploads `FlowMate-<sha>.zip` as a build artifact (14 days) |
| `release.yml` | a tag like `v1.2.0` | tests, build, Developer ID signing, notarization, `FlowMate-1.2.0.zip` on a GitHub Release, Sparkle appcast on the `gh-pages` branch |

To release: `git tag v1.2.0 && git push origin v1.2.0`. The tag is the marketing version; the build number is the UTC time, so it only grows.

## One-time setup

1. **Update signing key.** Build once (`./build-app.sh`), then run `.build/artifacts/sparkle/Sparkle/bin/generate_keys`. It stores the private key in your login keychain and prints the public key. Put the public key in `Resources/SparklePublicKey.txt` and commit it. Export the private key with `generate_keys -x sparkle_private.key`, save it in a password manager and delete the file. **Lose it and installed copies can't be updated** (they would need a manual download).
2. **Secrets** (Settings → Secrets and variables → Actions):
   - `SPARKLE_PRIVATE_KEY`: contents of the exported private key file
   - `DEVELOPER_ID_P12_BASE64`: your *Developer ID Application* certificate and key from Keychain Access, exported as .p12, then `base64 -i cert.p12 | pbcopy`
   - `DEVELOPER_ID_P12_PASSWORD`: the .p12 password
   - `APPLE_ID`, `APPLE_APP_PASSWORD` (an app-specific password from appleid.apple.com), `APPLE_TEAM_ID`
3. **GitHub Pages:** after the first release creates the `gh-pages` branch, Settings → Pages → deploy from branch `gh-pages`, root. The feed is then `https://as206em.github.io/FlowMate/appcast.xml` (the default `FEED_URL` in `build-app.sh`).

`ci.yml` works without any secret; it just signs ad-hoc.

## How an update goes

Sparkle reads the appcast, finds a higher build number, downloads the zip, checks its EdDSA signature and the app's code signature, then calls `UpdateService` just before installing. That copies the data folder (`workspace.json`, its `.bak`, `config.json`, project icons; not logs) to `~/Library/Application Support/FlowMate/Backups/<old>-before-<new>-<time>/`, keeps the newest 5, installs and relaunches. Settings → Updates lists the backups with **Restore…** (which backs up the current data first).

## Local builds

`./build-app.sh` signs with the Developer ID in your keychain when there is one, else with "FlowMate Dev Certificate". Environment variables (`VERSION`, `BUILD_NUMBER`, `SIGN_IDENTITY`, `UNIVERSAL=1`, `NO_LAUNCH=1`, …) are listed at the top of the script. Updates are off in a build without `Resources/SparklePublicKey.txt`.
