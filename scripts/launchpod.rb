cask "launchpod" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/__REPOSITORY__/releases/download/v#{version}/Launchpod-#{version}-universal.dmg"
  name "Launchpod"
  desc "Open-source Launchpad alternative"
  homepage "https://github.com/__REPOSITORY__"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :tahoe"

  app "Launchpod.app"

  zap trash: [
    "~/Library/Application Support/Launchpod",
    "~/Library/Caches/app.joyx.launchpod",
    "~/Library/HTTPStorages/app.joyx.launchpod",
    "~/Library/Preferences/app.joyx.launchpod.dock-icon.plist",
    "~/Library/Preferences/app.joyx.launchpod.plist",
  ]
end
