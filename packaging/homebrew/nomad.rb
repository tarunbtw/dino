cask "nomad" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/tarunbtw/nomad/releases/download/v#{version}/Nomad.zip"
  name "Nomad"
  desc "Ultra-lightweight native macOS WebKit browser engine and agent runtime"
  homepage "https://github.com/tarunbtw/nomad"

  depends_on macos: ">= :ventura"

  app "nomad.app", target: "Nomad.app"
  binary "#{appdir}/Nomad.app/Contents/MacOS/nomad", target: "nomad"
  binary "#{appdir}/Nomad.app/Contents/MacOS/nomad", target: "nomadd"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-r", "-d", "com.apple.quarantine", "#{appdir}/Nomad.app"],
                   sudo: false
  rescue StandardError
    # Ignore if quarantine attribute is absent
  end

  zap trash: [
    "~/.nomad",
    "~/Library/Application Support/Nomad",
    "~/Library/Caches/tarun.nomad",
    "~/Library/Preferences/tarun.nomad.plist",
    "~/Library/Saved Application State/tarun.nomad.savedState"
  ]
end
