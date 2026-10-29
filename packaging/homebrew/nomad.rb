cask "nomad" do
  version "0.15"
  sha256 "dd17e79ac56769f2c60480c44880e5a788068f8ccace459030cee1e78fc6c2cb"

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
