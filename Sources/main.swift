//
//  TermToggle
//
//  A pure-background macOS agent that binds one global hotkey to
//  show / hide / launch a terminal — any app, really. Ghostty by default.
//
//  Carbon's RegisterEventHotKey, not an event tap: it needs no Accessibility grant.
//

import AppKit
import Carbon.HIToolbox
import ServiceManagement
import os

// MARK: - Configuration

private enum Defaults {
    /// Preferences domain, read explicitly so it also works for an unbundled binary:
    ///   defaults write com.mihasic.term-toggle app net.kovidgoyal.kitty
    static let domain = "com.mihasic.term-toggle"

    /// App spec: a bundle id, an app name, or a path to an .app.
    static let app = "com.mitchellh.ghostty"

    /// Chord: modifier words joined by `+`, then a base key. A modifier is required.
    static let hotkey = "opt+grave"

    /// Four-char signature + id identifying our hotkey in the Carbon event.
    static let hotKeySignature: OSType = 0x5454_474C  // 'TTGL'
    static let hotKeyID: UInt32 = 1

    /// Per-session agent variables, never worth handing down to the target.
    static let poisonedEnvironmentPrefixes = ["CLAUDE", "_CLAUDE", "ANTHROPIC", "_ANTHROPIC", "AI_AGENT"]
}

private let log = Logger(subsystem: "com.mihasic.term-toggle", category: "toggle")

// MARK: - Command line

/// Parsed before the settings below resolve, because a flag outranks them all.
private enum Options {
    static var app: String?
    static var hotkey: String?
    static var commands: Set<String> = []

    static func parse() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        while let argument = arguments.first {
            arguments.removeFirst()
            // `--app=x` and `--app x` both work.
            let (name, inlineValue): (String, String?) = {
                guard let separator = argument.firstIndex(of: "=") else { return (argument, nil) }
                return (String(argument[argument.startIndex..<separator]),
                        String(argument[argument.index(after: separator)...]))
            }()
            func value() -> String {
                if let inlineValue { return inlineValue }
                guard let next = arguments.first, !next.hasPrefix("-") else {
                    fputs("TermToggle: \(name) needs a value\n", stderr)
                    exit(2)
                }
                arguments.removeFirst()
                return next
            }
            switch name {
            case "--app", "-a": app = value()
            case "--hotkey", "-k": hotkey = value()
            default: commands.insert(name)
            }
        }
    }
}

Options.parse()

// MARK: - Settings

/// Where a setting came from — printed by `--config`, so a surprise is diagnosable.
private enum Source: String {
    case flag, environment, defaults, builtIn = "built-in"
}

/// `suiteName` is a no-op for our own bundle id (AppKit warns and ignores it), so
/// use the standard domain inside the bundle and the explicit suite outside it —
/// that way an unbundled binary reads the same `defaults write ...` settings.
private let preferences: UserDefaults =
    Bundle.main.bundleIdentifier == Defaults.domain
        ? .standard
        : UserDefaults(suiteName: Defaults.domain) ?? .standard

/// Flag → environment → preferences → built-in default.
private func setting(flag: String?, env: String, key: String, fallback: String) -> (String, Source) {
    if let flag { return (flag, .flag) }
    if let value = ProcessInfo.processInfo.environment[env], !value.isEmpty { return (value, .environment) }
    if let value = preferences.string(forKey: key), !value.isEmpty { return (value, .defaults) }
    return (fallback, .builtIn)
}

private let (appSpec, appSource) = setting(
    flag: Options.app, env: "TERM_TOGGLE_APP", key: "app", fallback: Defaults.app)
private let (hotkeySpec, hotkeySource) = setting(
    flag: Options.hotkey, env: "TERM_TOGGLE_HOTKEY", key: "hotkey", fallback: Defaults.hotkey)

// MARK: - Target app

/// A resolved target: `url` is nil for a bundle id nothing on disk claims (yet).
private struct Target {
    let spec: String
    let bundleID: String
    let url: URL?
}

/// Accepts a bundle id (`net.kovidgoyal.kitty`), a bare app name (`kitty`), or a
/// path (`~/Applications/kitty.app`). Resolved on every toggle: the app may be
/// installed, moved or replaced while we run.
private func resolveTarget(_ spec: String) -> Target? {
    if spec.hasSuffix(".app") || spec.contains("/") {
        let url = URL(fileURLWithPath: (spec as NSString).expandingTildeInPath)
        guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        return Target(spec: spec, bundleID: id, url: url)
    }
    if spec.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: spec) {
        return Target(spec: spec, bundleID: spec, url: url)
    }
    for directory in ["/Applications", "\(NSHomeDirectory())/Applications", "/System/Applications"] {
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(spec).app")
        if let id = Bundle(url: url)?.bundleIdentifier {
            return Target(spec: spec, bundleID: id, url: url)
        }
    }
    // A bundle id whose app is not installed still gives a usable state machine.
    return spec.contains(".") ? Target(spec: spec, bundleID: spec, url: nil) : nil
}

// MARK: - Hotkey chord

private struct Hotkey {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String
}

private let keyCodes: [String: Int] = {
    var table: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "grave": kVK_ANSI_Grave, "`": kVK_ANSI_Grave,
        "minus": kVK_ANSI_Minus, "-": kVK_ANSI_Minus,
        "equal": kVK_ANSI_Equal, "=": kVK_ANSI_Equal,
        "leftbracket": kVK_ANSI_LeftBracket, "[": kVK_ANSI_LeftBracket,
        "rightbracket": kVK_ANSI_RightBracket, "]": kVK_ANSI_RightBracket,
        "backslash": kVK_ANSI_Backslash, "\\": kVK_ANSI_Backslash,
        "semicolon": kVK_ANSI_Semicolon, ";": kVK_ANSI_Semicolon,
        "quote": kVK_ANSI_Quote, "'": kVK_ANSI_Quote,
        "comma": kVK_ANSI_Comma, ",": kVK_ANSI_Comma,
        "period": kVK_ANSI_Period, ".": kVK_ANSI_Period,
        "slash": kVK_ANSI_Slash, "/": kVK_ANSI_Slash,
        "space": kVK_Space, "tab": kVK_Tab, "return": kVK_Return, "enter": kVK_Return,
        "escape": kVK_Escape, "esc": kVK_Escape,
        "delete": kVK_Delete, "backspace": kVK_Delete, "forwarddelete": kVK_ForwardDelete,
        "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
        "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
    ]
    let functionKeys = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
    ]
    for (index, code) in functionKeys.enumerated() { table["f\(index + 1)"] = code }
    return table
}()

/// `opt+grave`, `ctrl+shift+t`, `cmd+opt+space`. Key codes are physical positions,
/// so a chord survives a keyboard-layout switch.
private func parseHotkey(_ spec: String) -> Hotkey? {
    let parts = spec.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    guard let base = parts.last, let code = keyCodes[base] else { return nil }

    var modifiers: UInt32 = 0
    var names: [String] = []
    for token in parts.dropLast() {
        switch token {
        case "ctrl", "control": modifiers |= UInt32(controlKey); names.append("ctrl")
        case "opt", "option", "alt": modifiers |= UInt32(optionKey); names.append("opt")
        case "shift": modifiers |= UInt32(shiftKey); names.append("shift")
        case "cmd", "command": modifiers |= UInt32(cmdKey); names.append("cmd")
        default: return nil
        }
    }
    // A bare key would be swallowed system-wide, in every app, until we quit.
    guard modifiers != 0 else { return nil }
    return Hotkey(
        keyCode: UInt32(code), modifiers: modifiers, label: (names + [base]).joined(separator: "+"))
}

// MARK: - Target state

private enum TargetState {
    case notRunning
    case frontmost(NSRunningApplication)
    /// Hidden, behind other apps, or windowless — all handled by `showOrLaunch()`.
    case background(NSRunningApplication)
}

private func currentState(_ target: Target) -> TargetState {
    guard let app = NSRunningApplication
        .runningApplications(withBundleIdentifier: target.bundleID).first
    else { return .notRunning }
    // `isHidden` matters: a hidden app can still report isActive briefly.
    return app.isActive && !app.isHidden ? .frontmost(app) : .background(app)
}

// MARK: - Actions

/// Bring the target to the front, launching it if it isn't running and giving it a
/// window if it has none.
///
/// One LaunchServices open covers all three, and not `activate()`: the reopen
/// event lets AppKit decide whether a window is needed, which we cannot count
/// reliably ourselves. It unhides on the way too.
private func showOrLaunch(_ target: Target) {
    guard let url = target.url else {
        log.error("target not installed: \(target.spec, privacy: .public)")
        return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.createsNewApplicationInstance = false
    // Only consulted on a cold launch; a running app keeps its own env.
    configuration.environment = ProcessInfo.processInfo.environment.filter { key, _ in
        !Defaults.poisonedEnvironmentPrefixes.contains { key.hasPrefix($0) }
    }
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
        if let error {
            log.error("openApplication failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The whole point of the app. Called from the Carbon handler and from `--toggle`.
private func toggle() {
    guard let target = resolveTarget(appSpec) else {
        log.error("cannot resolve app: \(appSpec, privacy: .public)")
        return
    }
    switch currentState(target) {
    case .notRunning:
        log.notice("state: not running -> launch")
        showOrLaunch(target)
    case .frontmost(let app):
        log.notice("state: frontmost -> hide")
        app.hide()
    case .background:
        log.notice("state: background -> activate (and open a window if it has none)")
        showOrLaunch(target)
    }
}

// MARK: - Global hotkey (Carbon)

/// Kept alive for the process lifetime; unregistering is the OS's job at exit.
private var hotKeyRef: EventHotKeyRef?

/// Must capture nothing: `InstallEventHandler` takes a bare C function pointer.
private let hotKeyHandler: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }
    var received = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &received)
    guard status == noErr, received.id == Defaults.hotKeyID else {
        return OSStatus(eventNotHandledErr)
    }
    toggle()
    return noErr
}

private func registerHotKey(_ hotkey: Hotkey) -> Bool {
    var spec = EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed))

    let handlerStatus = InstallEventHandler(
        GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
    guard handlerStatus == noErr else {
        log.error("InstallEventHandler failed: \(handlerStatus)")
        return false
    }

    let id = EventHotKeyID(signature: Defaults.hotKeySignature, id: Defaults.hotKeyID)
    // Exclusive: a second TermToggle copy fails loudly instead of silently.
    // Other apps register non-exclusively, so their conflicts still go unseen.
    let status = RegisterEventHotKey(
        hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(),
        OptionBits(kEventHotKeyExclusive), &hotKeyRef)
    guard status == noErr else {
        // -9878 (eventHotKeyExistsErr): another TermToggle copy owns the chord.
        log.error("RegisterEventHotKey failed: \(status)")
        return false
    }
    return true
}

// MARK: - Login item

private func registerLoginItem() {
    let service = SMAppService.mainApp
    switch service.status {
    case .enabled:
        return  // already a login item; no-op
    case .requiresApproval:
        log.notice("login item awaiting approval in System Settings > General > Login Items")
        return
    default:
        do {
            try service.register()
            log.notice("registered as login item")
        } catch {
            log.error("login item registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private func unregisterLoginItem() {
    do {
        try SMAppService.mainApp.unregister()
        print("TermToggle: unregistered from login items.")
    } catch {
        print("TermToggle: unregister failed: \(error.localizedDescription)")
        exit(1)
    }
}

// MARK: - Entry point

private let commands = Options.commands

if commands.contains("--version") {
    // Set from ./VERSION at build time; only present when run inside the bundle.
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    print("TermToggle \(version ?? "unknown")")
    exit(0)
}

if commands.contains("--help") || commands.contains("-h") {
    print("""
    TermToggle — one global hotkey to show / hide / launch a terminal.

      (no flags)             run as a background agent and register the hotkey

      -a, --app <spec>       bundle id, app name, or path to an .app
      -k, --hotkey <chord>   e.g. opt+grave, ctrl+shift+t (a modifier is required)

      --toggle               perform one toggle and exit
      --state                print the detected state of the target app
      --config               print the resolved settings and where they came from
      --login-status         print the login-item registration status
      --unregister           remove from login items
      --no-login-item        run the agent without registering as a login item
      --version              print the version
      --help                 this message

    Settings resolve flag -> environment -> preferences -> built-in:

      TERM_TOGGLE_APP=net.kovidgoyal.kitty TermToggle --toggle
      defaults write \(Defaults.domain) app com.googlecode.iterm2
      defaults write \(Defaults.domain) hotkey "ctrl+shift+grave"

    Built-ins are \(Defaults.app) and \(Defaults.hotkey). A preferences
    change takes effect when the agent restarts.
    """)
    exit(0)
}

if commands.contains("--unregister") {
    unregisterLoginItem()
    exit(0)
}

if commands.contains("--login-status") {
    // Meaningful only when run from inside the installed bundle.
    switch SMAppService.mainApp.status {
    case .enabled: print("enabled")
    case .requiresApproval: print("requires-approval")
    case .notRegistered: print("not-registered")
    case .notFound: print("not-found")
    @unknown default: print("unknown")
    }
    exit(0)
}

private let target = resolveTarget(appSpec)
private let hotkey = parseHotkey(hotkeySpec)

/// Shared by `--state` and `--config`.
private func stateDescription(_ target: Target?) -> String {
    guard let target else { return "unresolved" }
    switch currentState(target) {
    case .notRunning: return "not-running"
    case .frontmost: return "frontmost"
    case .background(let app): return "background (hidden=\(app.isHidden))"
    }
}

if commands.contains("--config") {
    print("app     \(target?.bundleID ?? appSpec)  (\(target?.url?.path ?? "not installed"))  [\(appSource.rawValue)]")
    print("hotkey  \(hotkey?.label ?? "invalid: \(hotkeySpec)")  [\(hotkeySource.rawValue)]")
    print("state   \(stateDescription(target))")
    exit(0)
}

if commands.contains("--state") {
    print(stateDescription(target))
    exit(0)
}

if let unknown = commands.first(where: { $0 != "--toggle" && $0 != "--no-login-item" }) {
    fputs("TermToggle: unknown option \(unknown) — see --help\n", stderr)
    exit(2)
}

guard let target else {
    fputs("TermToggle: no app found for '\(appSpec)' — pass a bundle id, an app name, or a path\n", stderr)
    exit(1)
}

if commands.contains("--toggle") {
    // One-shot: run the state machine without installing a hotkey.
    toggle()
    // Give the async openApplication callback a moment to fire.
    RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    exit(0)
}

guard let hotkey else {
    fputs("TermToggle: cannot parse hotkey '\(hotkeySpec)' — e.g. opt+grave, ctrl+shift+t\n", stderr)
    exit(1)
}

let application = NSApplication.shared
// Must happen before run(): no Dock icon, no menu bar, no windows.
application.setActivationPolicy(.accessory)

guard registerHotKey(hotkey) else {
    fputs("TermToggle: could not register \(hotkey.label) — is another TermToggle running?\n", stderr)
    exit(1)
}

if !commands.contains("--no-login-item") {
    registerLoginItem()
}

log.notice("TermToggle running; \(hotkey.label, privacy: .public) -> \(target.bundleID, privacy: .public)")
application.run()
