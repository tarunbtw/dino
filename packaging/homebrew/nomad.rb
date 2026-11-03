cask "nomad" do
  version "0.28"
  sha256 "c3f90730345b772316bc747853844bfa76c7e93263034964c18976bc2d56d385"

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
