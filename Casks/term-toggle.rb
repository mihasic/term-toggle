# Updated automatically by .github/workflows/release.yml on each tagged release.
cask "term-toggle" do
  version "0.1.1"
  sha256 "f00cc3d528ff902b7d644058d9031369d8c7ac82b8254f2ab9871bb6c2720832"

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
