# 参与 Launchpod 贡献

[English](CONTRIBUTING.md) | [简体中文](CONTRIBUTING.zh-Hans.md)

感谢你帮助改进 Launchpod。本指南说明如何反馈问题、提出修改，以及让 PR 顺利合并。

## 贡献者许可协议

PR 合并前，你需要签署[贡献者许可协议](CLA.zh-Hans.md)（CLA）。你第一次提交 PR 时，CLA 机器人会留言；按它的要求回复指定的那句话即可完成签署。只需签署一次，之后的所有贡献都适用。

## 反馈问题和功能建议

请先搜索[已有的 issue](https://github.com/callumhxu/launchpod/issues)。新建 issue 时请附上：

- macOS 版本和 Mac 机型（Apple 芯片或 Intel）
- 设置 › 关于里显示的 Launchpod 版本
- 复现步骤、预期结果和实际结果
- 界面问题请附截图或录屏

## 开发环境

参见 README 中的[从源码编译](README.zh-Hans.md#从源码编译)。提交 PR 前请先运行单元测试：

```sh
xcodebuild test -project apps/macOS/Launchpod.xcodeproj -scheme Launchpod
```

## 提交 PR

- 每个 PR 只做一件事，并说明改了什么、为什么改。
- 行为有变化时，请新增或更新测试。单元测试的目录与源码一一对应，例如 `Launchpod/ClassicalMode/Grid/Foo.swift` 的测试放在 `LaunchpodTests/ClassicalMode/Grid/FooTests.swift`。
- 遵循周围代码的风格和命名，不要重新格式化无关代码。
- 不要新增网络访问。Launchpod 唯一的网络连接是 Sparkle 的更新检查。
- 确保编译没有新增警告。

## 本地化

Launchpod 支持英文、简体中文、繁体中文、法文、德文、日文、韩文和西班牙文。界面文字通过 Swift 的本地化 API 使用英文原文，由 Xcode 提取到 `apps/macOS/Launchpod/Resources/Localizable.xcstrings`。新增或修改的文字需要补齐全部八种语言的翻译，对应功能才算完成。请在 Xcode 的 String Catalog 编辑器中编辑翻译，不要手动改文件。

## 许可证

提交贡献即表示你同意你的贡献以 [GNU 通用公共许可证 v3.0](LICENSE) 授权，并适用 [CLA](CLA.zh-Hans.md) 的条款。
