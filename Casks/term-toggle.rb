# Updated automatically by .github/workflows/release.yml on each tagged release.
cask "term-toggle" do
  version "0.1.4"
  sha256 "477a1cdcff3fb41d625679874f2e43d85e0d0ed7e8e51d5ac9ff20362769125b"

  url "https://github.com/mihasic/term-toggle/releases/download/v#{version}/TermToggle-#{version}.dmg"
  name "TermToggle"
  desc "Global hotkey to show, hide, or launch a terminal"
  homepage "https://github.com/mihasic/term-toggle"

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "TermToggle.app"

  # Ad-hoc signed, not notarized: strip the download quarantine or Gatekeeper
  # refuses to launch it. Homebrew 7 sandboxes install steps, so it cannot
  # also `open` the app for us — the caveat asks the user to.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/TermToggle.app"]
  end

  uninstall quit:   "com.mihasic.term-toggle",
            script: {
              executable: "#{appdir}/TermToggle.app/Contents/MacOS/TermToggle",
              args:       ["--unregister"],
            }

  caveats <<~EOS
    Start it now (after an install or upgrade); it starts at login from then on:
      open -a TermToggle
  EOS
end
