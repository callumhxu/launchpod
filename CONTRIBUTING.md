# Contributing to Launchpod

[English](CONTRIBUTING.md) | [简体中文](CONTRIBUTING.zh-Hans.md)

Thank you for helping improve Launchpod. This guide covers how to report problems, propose changes, and get a pull request merged.

## Contributor License Agreement

Before a pull request can be merged, you must sign the [Contributor License Agreement](CLA.md). The CLA bot comments on your first pull request; reply with the sentence it asks for to sign. You sign once, and the signature covers all of your future contributions.

## Reporting bugs and requesting features

Search [existing issues](https://github.com/callumhxu/launchpod/issues) first. When opening a new issue, include:

- your macOS version and Mac model (Apple silicon or Intel)
- the Launchpod version from Settings › About
- the steps to reproduce, what you expected, and what happened
- screenshots or a screen recording for visual problems

## Development setup

See [Building from source](README.md#building-from-source) in the README. Run the unit tests before opening a pull request:

```sh
xcodebuild test -project apps/macOS/Launchpod.xcodeproj -scheme Launchpod
```

## Pull requests

- Keep each pull request focused on one change, and explain what it changes and why.
- Add or update tests for behavior changes. Unit tests mirror the source directories, so `Launchpod/ClassicalMode/Grid/Foo.swift` is tested in `LaunchpodTests/ClassicalMode/Grid/FooTests.swift`.
- Follow the surrounding code's style and naming. Do not reformat unrelated code.
- Do not add network access. Launchpod's only network connection is the Sparkle update check.
- Make sure the project builds without new warnings.

## Localization

Launchpod ships in English, Simplified Chinese, Traditional Chinese, French, German, Japanese, Korean, and Spanish. User-facing text uses English source strings through Swift's localization APIs, and Xcode extracts them into `apps/macOS/Launchpod/Resources/Localizable.xcstrings`. A new or changed string needs translations in all eight languages before its feature is complete. Edit translations in Xcode's String Catalog editor rather than by hand.

## License

By contributing, you agree that your contributions are licensed under the [GNU General Public License v3.0](LICENSE) and under the terms of the [CLA](CLA.md).
