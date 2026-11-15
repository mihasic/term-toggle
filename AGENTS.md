# Repository guidance

TermToggle is a background macOS agent that uses a Carbon global hotkey to show,
hide, or launch a configurable application. Ghostty is the default target.

## Layout

- `Sources/main.swift` contains the application, CLI, configuration, and hotkey logic.
- `Resources/Info.plist` defines the app bundle.
- `build.sh` compiles and signs the Apple Silicon app for macOS 13 or later.
- `VERSION` is the source of truth for the release version.
- `Casks/term-toggle.rb` and `.github/workflows/` handle distribution and CI.

## Development

Keep the app dependency-free, with no Xcode project or SwiftPM package. Preserve
the background-only behavior and Carbon hotkey registration, which needs no
Accessibility permission. Use LaunchServices to activate or reopen target apps
instead of counting windows. Scrub terminal session environment variables before
launching targets. Update README.md when configuration or CLI behavior changes.

## Verification

Run `./build.sh --no-install` to compile and verify the signed bundle without
installing it or starting a login item. The default build command installs and
launches the app, so use it only when installation is requested.

Smoke-test the binary at `build/TermToggle.app/Contents/MacOS/TermToggle` with
`--version` and `--config`. Check a specific target with `--app <spec> --config`.
Unknown options must exit unsuccessfully. Use `--toggle` only when intentionally
testing a visible change to the target application.
