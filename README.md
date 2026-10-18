<div align="center">
  <img src="apps/macOS/Launchpod/Assets.xcassets/AppIcon.appiconset/AppIcon-512.png" width="128" height="128" alt="Launchpod icon">
  <h1>Launchpod</h1>
  <p><strong>Your Launchpad. Back on your Mac.</strong></p>
  <p>A free, open-source Launchpad alternative for macOS 26 and macOS 27.</p>
  <p>
    <a href="https://github.com/callumhxu/launchpod/releases/latest"><img src="https://img.shields.io/github/v/release/callumhxu/launchpod?label=release" alt="Latest release"></a>
    <a href="https://github.com/callumhxu/launchpod/releases"><img src="https://img.shields.io/github/downloads/callumhxu/launchpod/total" alt="Downloads"></a>
    <img src="https://img.shields.io/badge/macOS-26%2B-blue" alt="macOS 26 or later">
    <a href="LICENSE"><img src="https://img.shields.io/github/license/callumhxu/launchpod" alt="License"></a>
  </p>
  <p><a href="README.md">English</a> | <a href="README.zh-Hans.md">简体中文</a></p>
</div>

Launchpod brings back the familiar full-screen grid of your apps. Arrange them in pages and folders, then find what you need at a glance or with a quick search. It is a native Mac app, built with Swift, AppKit, and Core Animation, so it opens instantly, animates smoothly, and feels right at home on your Mac.

![Launchpod demo: app grid, search, and folders](assets/launchpod-demo.gif)

[Watch the MP4 demo](assets/launchpod-demo.mp4)

**[Download the latest release](https://github.com/callumhxu/launchpod/releases/latest)**

## Features

- **The grid you know.** Your work and everyday apps together in a full-screen, paged grid in Classical mode.
- **Folders and pages.** Keep related apps together, and rearrange everything with drag and drop.
- **Search.** Find an app by name, right from the launcher. Your layout stays where you left it.
- **Make it yours.** Adjust the icon grid, add app directories, and choose the appearance and app icon.
- **Quick access.** Open Launchpod from the Dock, the menu bar, or a global keyboard shortcut.
- **Layout backup.** Export, import, and restore your arrangement from Advanced settings.
- **Eight languages.** English, Simplified Chinese, Traditional Chinese, French, German, Japanese, Korean, and Spanish, selectable in Settings independently of the system language.
- **Free and open source.** No subscription, no account, no trial. Licensed under GPL-3.0.
- **Automatic updates.** Signed updates are delivered through [Sparkle](https://sparkle-project.org).

## FAQ

**How is Launchpod different from Spotlight?**
Spotlight searches across your whole Mac. Launchpod gives your apps a dedicated grid you can browse and organize into pages and folders. You can use both.

**Which macOS versions are supported?**
macOS 26 and later, including macOS 27.

**Is it really free?**
Yes. Launchpod is free and open source under the GPL-3.0 license.

## Privacy

Launchpod does not collect data and has no account. The only network connection it makes is the Sparkle update check. Links in Settings › About open in your browser.

## Requirements

- macOS 26 or later
- Apple silicon or Intel (universal build)

## Installation

Install with [Homebrew](https://brew.sh):

```sh
brew install --cask callumhxu/tap/launchpod
```

Or download the latest `Launchpod-<version>-universal.dmg` from [Releases](https://github.com/callumhxu/launchpod/releases), open it, and drag Launchpod to Applications. Release builds are signed with a Developer ID and notarized by Apple.

When you delete an app from Launchpod, macOS asks once for permission to let Launchpod control Finder, which moves the app to the Trash.

## Building from source

1. Install Xcode 27 or later.
2. Clone the repository:

   ```sh
   git clone https://github.com/callumhxu/launchpod.git
   ```

3. Open `apps/macOS/Launchpod.xcodeproj`, select the `Launchpod` scheme, and run it. Xcode resolves the Sparkle package automatically.

Local builds have no update feed configured, so Check for Updates stays unavailable. To sign the app with your own team, set it in the target's Signing & Capabilities.

### Running tests

Unit tests run on macOS 27 or later:

```sh
xcodebuild test -project apps/macOS/Launchpod.xcodeproj -scheme Launchpod
```

Some tests open native windows and skip themselves when the session cannot show them.

## Project structure

| Path | Contents |
| --- | --- |
| `apps/macOS/Launchpod` | App source: Classical mode, settings, onboarding, shared domain, and system integration |
| `apps/macOS/Extensions` | Dock tile plug-in |
| `apps/macOS/LaunchpodTests` | Unit tests, mirroring the source directories |
| `apps/macOS/LaunchpodUITests` | UI tests |
| `scripts` | Release build script, its settings, and the Homebrew cask template |
| `.github/workflows` | Signed, notarized release on version tags, and CLA signing on pull requests |

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first; every contributor signs the [Contributor License Agreement](CLA.md) once, in the pull request.

## License

Launchpod is licensed under the [GNU General Public License v3.0](LICENSE).

## Disclaimer

Launchpod is an independent open-source project developed by Callum Xu. It is not affiliated with Apple Inc.

Apple, Mac, macOS, and Launchpad are trademarks of Apple Inc. GitHub, X, YouTube, TikTok, and other names and logos mentioned here are trademarks of their respective owners.

Launchpod is free to use, with no guarantee of availability or suitability for your needs. The author accepts no liability for problems arising from its use. See the [license](LICENSE) for details.

## Links

- GitHub: [callumhxu/launchpod](https://github.com/callumhxu/launchpod)
- X: [@callumhxu](https://x.com/callumhxu)
- YouTube: [@callumhxu](https://www.youtube.com/@callumhxu)
- TikTok: [@callumhxu](https://www.tiktok.com/@callumhxu)
