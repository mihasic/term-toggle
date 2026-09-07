# Updated automatically by .github/workflows/release.yml on each tagged release.
cask "term-toggle" do
  version "0.1.0"
  sha256 "584321536dce8396783d1bf66d0d7732f9b1a0e582f7896a23fc3ab02ac10d67"

  url "https://github.com/mihasic/term-toggle/releases/download/v#{version}/TermToggle-#{version}.dmg"
  name "TermToggle"
  desc "Global hotkey to show, hide, or launch a terminal"
  homepage "https://github.com/mihasic/term-toggle"

  depends_on macos: :ventura

  app "TermToggle.app"

  # Ad-hoc signed, not notarized: strip the download quarantine or Gatekeeper
  # refuses to launch it. Then start it, so the hotkey works without a reboot.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/TermToggle.app"]
    run "/usr/bin/open", args: ["{{appdir}}/TermToggle.app"]
  end

  uninstall quit:   "com.mihasic.term-toggle",
            script: {
              executable: "#{appdir}/TermToggle.app/Contents/MacOS/TermToggle",
              args:       ["--unregister"],
            }
end
