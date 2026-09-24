# TermToggle

One global hotkey — **⌥`** (Option + backtick) by default — to show, hide, or
launch your terminal, from anywhere in macOS.

| The app is… | ⌥` does |
| --- | --- |
| Not running | Launches it |
| Behind another app | Brings it to the front |
| In front of you | Hides it |
| Running with no windows | Brings it up **and** opens a new window |

Any app works; the built-in target is [Ghostty](https://ghostty.org). Point it at
iTerm2, kitty, or anything else with one `defaults write` — see
[Configuration](#configuration).

It runs in the background: no Dock icon, no menu bar item, no windows, and no
permission prompts. Starts automatically at login.

**Why not the terminal's own global keybind?** Ghostty's `global:` prefix and kitty's
quick-access window handle rows 2 and 3, but neither can launch the app when it isn't
running — there's no process there to receive the key. And both summon a quake-style
panel rather than your real windows. This fills that gap.

## Install

```sh
brew tap mihasic/term-toggle https://github.com/mihasic/term-toggle
brew trust mihasic/term-toggle
brew install --cask term-toggle
open -a TermToggle
```

Homebrew requires the explicit `brew trust` for any tap outside the official ones, and
sandboxes cask install steps, so it cannot start the app for you.

⌥` works as soon as it's open, and TermToggle starts at login from then on.
macOS may ask you to approve it once under **System Settings → General → Login
Items & Extensions**.

Requires macOS 13 (Ventura) or later. Apple Silicon and Intel.

### Upgrade

```sh
brew upgrade --cask term-toggle
open -a TermToggle
```

### Uninstall

```sh
brew uninstall --cask term-toggle
```

This also removes it from your login items.

### Without Homebrew

Download the DMG from [Releases](https://github.com/mihasic/term-toggle/releases),
drag **TermToggle** to Applications, then clear the download quarantine and launch it:

```sh
xattr -dr com.apple.quarantine /Applications/TermToggle.app
open /Applications/TermToggle.app
```

The app is ad-hoc signed rather than notarized (no paid Apple Developer account), so
without that `xattr` step Gatekeeper refuses to open it. The Homebrew cask does it for
you.

## Configuration

Two settings — the target app and the chord — each resolved
**flag → environment → preferences → built-in**:

```sh
defaults write com.mihasic.term-toggle app com.googlecode.iterm2
defaults write com.mihasic.term-toggle hotkey "ctrl+shift+grave"
```

Then restart the agent so it picks them up and re-registers the chord:

```sh
pkill -x TermToggle; open -a TermToggle
TermToggle --config          # what it actually resolved, and from where
```

`app` takes a bundle id (`net.kovidgoyal.kitty`), a bare app name (`kitty`), or a path
to a bundle (`~/Applications/kitty.app`). Common ids:

| Terminal | Bundle id |
| --- | --- |
| Ghostty (built-in default) | `com.mitchellh.ghostty` |
| iTerm2 | `com.googlecode.iterm2` |
| kitty | `net.kovidgoyal.kitty` |
| Apple Terminal | `com.apple.Terminal` |

`hotkey` is modifier words joined by `+`, then a base key: `ctrl`, `opt` (`alt`),
`shift`, `cmd`, and a key name — `a`–`z`, `0`–`9`, `grave`, `space`, `tab`, `return`,
`escape`, `delete`, an arrow, `f1`–`f12`, or a punctuation name (`minus`, `slash`, …).
A modifier is required, and keys are physical positions, so a chord survives a
keyboard-layout switch.

The environment variables `TERM_TOGGLE_APP` and `TERM_TOGGLE_HOTKEY` override the
preferences, but only for a run started from a shell — a login-item launch gets no
shell environment, which is what `defaults write` is for.

### Combos worth avoiding

⌃` is the usual quake-terminal binding, and also **toggle integrated terminal** in
VS Code, Zed and JetBrains IDEs. A global hotkey is grabbed system-wide, so binding ⌃`
here would silently kill the terminal toggle in every editor. ⌥` is unclaimed and keeps
the one-modifier muscle memory; its only cost is the grave-accent dead key (⌥` then `a`
→ à). Also taken: ⌘` (cycle windows in an app), ⌘Space (Spotlight), ⌥Space
(Raycast/Alfred), ⌃Space (input source, IDE completion).

If it exits with *"could not register"*, another TermToggle copy already owns that
combination. Any other app that grabs the same chord wins or loses **silently** — so
give your terminal's own quick-terminal binding a **different** chord. In Ghostty's config:

```
keybind = global:ctrl+shift+grave_accent=toggle_quick_terminal
```

A running Ghostty holds its old binding until you restart it; reloading the config is
not enough.

## Command line

```
TermToggle                    run as background agent (default)
TermToggle --toggle           perform one toggle and exit — scriptable, no hotkey
TermToggle --state            print the detected state of the target app
TermToggle --config           print the resolved settings and where they came from
TermToggle --login-status     print the login-item registration status
TermToggle --unregister       remove from login items
TermToggle --no-login-item    run as agent without registering as a login item
TermToggle --version
TermToggle --help

  -a, --app <spec>            override the target for this run
  -k, --hotkey <chord>        override the chord for this run
```

The binary lives at `/Applications/TermToggle.app/Contents/MacOS/TermToggle`.

Watch what it's doing:

```sh
log stream --predicate 'subsystem == "com.mihasic.term-toggle"' --info
```

## Build from source

```sh
./build.sh               # build, sign, install to ~/Applications, launch
./build.sh --no-install  # build only
./build.sh --dmg         # build and package build/TermToggle-<version>.dmg
```

Needs the Xcode command line tools (Swift 6.x). ~450 lines of Swift, one `swiftc`
invocation per architecture — no Xcode project, no SwiftPM, no dependencies.

`build.sh` installs to `~/Applications`, so uninstall the Homebrew copy first
(`brew uninstall --cask term-toggle`) — two copies fight over the hotkey and the loser
fails silently.

Releases are cut by tagging: `git tag v$(cat VERSION) && git push origin v$(cat VERSION)`.
[`.github/workflows/release.yml`](.github/workflows/release.yml) builds the universal
DMG, publishes it, and updates [`Casks/term-toggle.rb`](Casks/term-toggle.rb).

## Design notes

- **`RegisterEventHotKey`, not an event tap.** This needs no Accessibility / Input
  Monitoring grant. A `CGEvent` tap would prompt on first run and lose the grant on
  every rebuild, since TCC keys on the code signature.
- **Two apps cannot share a combo, and the loser fails silently.** Both registrations
  return `noErr`; only the first one to register receives the key. TermToggle registers
  with `kEventHotKeyExclusive`, which catches only another exclusive registrant — i.e.
  a second TermToggle copy.
- **A quick-terminal panel is a separate window class.** `NSApplication.hide()` does
  not hide it, so ⌥` will not put away a lone Ghostty quick terminal or kitty
  quick-access window. Out of scope by design.
- **No window counting.** `CGWindowListCopyWindowInfo` cannot answer "does this app
  have windows?" — `.optionAll` reports buffers of closed windows, `.optionOnScreenOnly`
  omits other Spaces. A single LaunchServices open covers rows 1, 2 and 4 instead;
  AppKit itself decides whether a reopen needs a new window.
- **The target is resolved on every press.** The app can be installed, moved or
  replaced while the agent runs, and a bundle id that is not installed yet still
  reports a sane state instead of failing to start.

## License

MIT — see [LICENSE](LICENSE).
