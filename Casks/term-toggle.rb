# Updated automatically by .github/workflows/release.yml on each tagged release.
cask "term-toggle" do
  version "0.1.5"
  sha256 "589291611917e6273dd930d850158d01aa4ca51a6804d43c03f5f306cee8514b"

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
