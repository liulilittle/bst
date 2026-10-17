# bst

> 中文 | [English](README.md)

[![ci](https://github.com/liulilittle/bst/actions/workflows/ci.yml/badge.svg)](https://github.com/liulilittle/bst/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

`bst` 是面向"C/C++ 难编译库"的跨平台构建工具集。拿到仓库,跑**一条命令**,
就能为目标平台编出正确产物——源码校验、工具链定位、上游坑位处理、产物暂存,
全部自动化。不需要研究,不需要折腾半天;知识都固化在脚本里。

## 快速开始

| 宿主 | 命令 |
| --- | --- |
| Linux / WSL | `scripts/build.sh openssl --site linux-aarch64` |
| macOS | `scripts/build.sh jemalloc --site macos-arm64` |
| Windows(PowerShell) | `.\scripts\build.ps1 openssl -Site windows-msvc-x64` |
| Windows → Linux/Android | 同上传 Linux 站点;`build.ps1` 自动经 WSL 委托执行 |

新机器首次准备:

```sh
# Linux / WSL:交叉工具链、qemu、NDK、liburing 测试所需的 libbpf/bpftool
scripts/setup.sh --all

# Windows:build.ps1 自行加载 MSVC 环境(需要 Visual Studio 2022),
# 缺 NASM 与 Strawberry Perl 时自动下载便携版。
```

全部选项与示例见 [docs/building.zh-CN.md](docs/building.zh-CN.md)。

## 支持库

| 库 | 事实来源 | 备注 |
| --- | --- | --- |
| [openssl](https://www.openssl.org) | 固定的 release 包 + sha256 | 按站点选择 Configure 目标;含 `apps/openssl` |
| [jemalloc](https://jemalloc.net) | 固定的 release 包 + sha256 | Unix 走 autotools;Windows 走官方 MSVC 方案;Android 以 `--disable-cxx` 构建(绕开 bionic 的 `malloc_usable_size` nothrow 冲突) |
| [liburing](https://github.com/axboe/liburing) | 固定 tag 包 + sha256 | 仅 Linux;可按需运行上游测试套件 |

每个库产物暂存在 `dist/<库>/<triple>/`,含 `include/`、`lib/`、`bin/`
与 `BUILD-INFO.txt`(记录精确版本、站点、编译参数与源码校验和)。

## 支持平台

宿主编自己名下的平台;其余一律明确拒绝并给出指引(Windows 宿主经 WSL
委托 Linux/Android 站点)。

| 平台 | 站点 | 库 |
| --- | --- | --- |
| Linux x86_64(原生) | gcc、clang | openssl、jemalloc、liburing |
| Linux 交叉(qemu 验证冒烟) | aarch64、armv7hf、riscv64、ppc64le、s390x、i686 | openssl、jemalloc、liburing |
| Windows MSVC | x64、x86、arm64 | openssl(x64/x86/arm64)、jemalloc(x64/x86) |
| macOS | arm64(Apple Silicon)、x64 | openssl、jemalloc |
| Android NDK(API 24) | arm64-v8a、armeabi-v7a、x86_64、x86 | openssl、jemalloc |

含验证级别的完整矩阵见 [docs/platforms.zh-CN.md](docs/platforms.zh-CN.md)。

## 从 CI 拿预编译产物

每次 CI 构建**按站点上传**产物包(`bst-<库>-<版本>-<triple>.tar.gz`):
打开对应的 workflow run,在 *Artifacts* 区下载即可。打 tag 发版
(`git tag v0.1.0`)会跑同一矩阵,把全部产物与 `SHA256SUMS` 附到 GitHub
Release。

## 扩展工具箱

新增一个库是一张清单,不是一个工程:一个配方文件、每个受支持站点一行
站点表、CI 矩阵行、一个冒烟测试。见
[docs/adding-a-library.zh-CN.md](docs/adding-a-library.zh-CN.md)。

上游需要补丁才能编?把 patch 丢进 `patches/<库>/` 即被自动应用(并做校验
戳记),解压之后、构建之前生效。

## 仓库结构

```
scripts/build.sh          主入口(Linux/WSL/macOS)
scripts/build.ps1         主入口(Windows;经 WSL 委托)
scripts/setup.sh          宿主一键准备
scripts/setup-ndk.sh      固定版本 Android NDK 获取
scripts/pin.sh            固定新上游版本(升级路径)
scripts/lib/recipes/      每库一个配方
ci/site-matrix.env        站点唯一事实来源
ci/versions.env           版本 + sha256 台账
patches/                  可选的上游构建修复
docs/                     双语文档
```

## 许可

MIT(见 [LICENSE](LICENSE));上游库各自保留其许可证
(见 [THIRD-PARTY.md](THIRD-PARTY.md))。
