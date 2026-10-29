cask "nomad" do
  version "0.19"
  sha256 "afc39b9cd855b95998d902d08b0b817d048e1905d9fa119a5379b20a0d1503af"

  url "https://github.com/tarunbtw/nomad/releases/download/v#{version}/Nomad-#{version}.zip"
  name "Nomad"
  desc "Ultra-lightweight native macOS WebKit browser engine and agent runtime"
  homepage "https://github.com/tarunbtw/nomad"

  depends_on macos: :ventura

  app "Nomad.app"
  binary "#{appdir}/Nomad.app/Contents/MacOS/nomad", target: "nomad"
  binary "#{appdir}/Nomad.app/Contents/MacOS/nomad", target: "nomadd"

  postflight_steps do
    on_macos do
      run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Nomad.app"]
    end
  end

  zap trash: [
    "~/.nomad",
    "~/Library/Application Support/Nomad",
    "~/Library/Caches/tarun.nomad",
    "~/Library/Preferences/tarun.nomad.plist",
    "~/Library/Saved Application State/tarun.nomad.savedState"
  ]
end
