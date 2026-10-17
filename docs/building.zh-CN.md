# 用 bst 构建库

> 中文 | [English](building.md)

本文覆盖构建入口的全部行为:环境要求、选项、各宿主工作流、产物、测试、
升级、补丁与故障排查。受支持站点矩阵见
[platforms.zh-CN.md](platforms.zh-CN.md);扩展契约见
[adding-a-library.zh-CN.md](adding-a-library.zh-CN.md)。

## 环境要求

| 宿主 | 需要 | 一键准备 |
| --- | --- | --- |
| Linux | gcc/make/curl/tar;交叉站点另需交叉工具链与 `qemu-user`;Android 站点需 NDK | `scripts/setup.sh --all` |
| WSL(Windows) | 同 Linux(推荐 Ubuntu 24.04);装包需要 `sudo` | 在 WSL 内执行 `scripts/setup.sh --all` |
| macOS | Xcode Command Line Tools(`xcode-select --install`) | — |
| Windows | Visual Studio 2022(含 C++ 桌面工作负载);Git for Windows(提供 bash) | `scripts/build.ps1` 自动加载 MSVC 环境,缺 NASM 与 Strawberry Perl 时自动下载便携版(`winget install NASM.NASM` / `StrawberryPerl.StrawberryPerl` 亦可) |

除此之外无需任何研究:所有下载都是固定版本、经 sha256 校验的上游源码包。

## 一条命令

```sh
scripts/build.sh <openssl|jemalloc|liburing> [选项]
```

| 选项 | 含义 |
| --- | --- |
| `--site <site>` | 目标站点(默认:本宿主的原生站点);`scripts/build.sh <库> --list-sites` 列出全部 |
| `--version <v>` | 上游版本;必须已在 `ci/versions.env` 固定(各库有默认值) |
| `--variant static\|shared\|both` | 库形态(默认 `static`) |
| `--test` | 追加运行上游测试套件(见下文*测试*) |
| `--clean` | 先清掉该库的构建树与暂存产物 |
| `--jobs <n>` | 并行度(默认:全部核心) |
| `--skip-smoke` | 跳过消费方冒烟测试 |
| `--list-sites` | 打印该库支持的全部站点 |

Windows 上用 PowerShell 入口:

```powershell
.\scripts\build.ps1 openssl -Site windows-msvc-x64
.\scripts\build.ps1 jemalloc -Site windows-msvc-x86 -Variant both
.\scripts\build.ps1 liburing -Site linux-aarch64     # 自动委托给 WSL
.\scripts\build.ps1 openssl -All                     # 本机可编的全部站点
```

`build.ps1` 与 bash 入口选项一一对应(`-Version`、`-Variant`、`-Test`、
`-Clean`、`-SkipSmoke`、`-WslDistro <名称>`、`-NoWsl`)。

## 宿主/目标策略

Windows 宿主编 Windows 站点;Linux 宿主(含 WSL)编 Linux 与 Android 站点;
macOS 宿主编 macOS 站点。请求不匹配时立即失败并给出该用的命令;
`build.ps1` 会自动完成 WSL 委托(`-NoWsl` 关闭该行为)。

## 产物

```
dist/<库>/<triple>/
  include/            公共头文件(安装布局)
  lib/                静态和/或动态库
  bin/                随库发布的工具(openssl)
  BUILD-INFO.txt      版本、站点、triple、形态、编译器、源码包 sha256
```

- `ci-logs/<库>-<站点>.log` — 完整构建日志。
- `.cache/src/` — 已校验的上游包(跨次构建复用)。
- `.build/` — 构建树(`--clean` 会清掉)。

WSL 下当仓库位于 `/mnt/*`(Windows 盘)时,构建树与缓存会自动放到 Linux
文件系统(`$HOME/.cache/bst/...`),因为 drvfs 对构建树而言慢到不可接受;
`dist/` 与日志则留在仓库内,方便 Windows 侧直接取用。可用
`BST_BUILD=<目录>` / `BST_CACHE=<目录>` 覆盖。

## 测试

`--test` 启用上游测试套件;具体跑什么取决于库与站点:

| 库 | Linux/macOS 原生 | 交叉站点 | Windows |
| --- | --- | --- | --- |
| openssl | `make test`(完整 perl 测试架) | 仅冒烟(测试架不支持 qemu) | `nmake test` |
| jemalloc | `make check`(单元套件) | 仅冒烟 | 仅冒烟(上游套件尚未接入 MSVC) |
| liburing | `runtests.sh` 精选子集(跨内核稳定);`BST_LIBURING_TESTS=all` 跑全量;`BST_LIBURING_TEST_EXCLUDE="t1 t2"` 排除 | 仅冒烟 | 不适用(仅 Linux) |

每个站点无论如何都会构建并运行**消费方冒烟测试**:一个针对暂存产物编译、
按真实消费方式链接、并实际运行的小程序(交叉站点经 `qemu-user` 与交叉
sysroot 运行;Android 只链接不运行——未接入设备运行器)。

liburing 的 cBPF 测试需要一致的现代 libbpf + bpftool 配对(Ubuntu 24.04
自带 libbpf 1.3,低于套件预期);`scripts/setup.sh --with-libbpf` 会从源码
构建固定的一对。

## 从 CI 拿预编译产物

- **Workflow 产物**:每次 CI 任务上传
  `bst-<库>-<版本>-<triple>.tar.gz`(Actions → run → Artifacts)。
- **Release**:推 tag(`git tag v0.1.0 && git push origin v0.1.0`),
  release 工作流跑完整矩阵,把全部产物与 `SHA256SUMS` 附到 GitHub Release。

## 升级库版本

```sh
scripts/pin.sh openssl 4.0.3 --update-default   # 下载、算 sha256、入账
scripts/build.sh openssl --site linux-x86_64    # 构建
```

`pin.sh` 把 `库|版本|url|sha256` 行追加进 `ci/versions.env`;不加
`--update-default` 时新版本需要通过 `--version 4.0.3` 显式选用。构建会校验
校验和,不匹配即失败(不静默继续)。

## 打补丁

把 `-p1` 统一 diff 放进 `patches/<库>/<版本>/`(仅该版本)或
`patches/<库>/`(全部版本);解压后按文件名顺序自动应用。改动补丁集后需
`--clean`(源码树带戳记,防止重复应用)。详见
[patches/README.md](../patches/README.md)。

## 宿主准备

```sh
scripts/setup.sh --all            # 基础工具 + 交叉工具链 + NDK + libbpf
scripts/setup.sh --with-cross     # 仅 apt 交叉工具链 + qemu-user
scripts/setup.sh --with-android   # 固定版本 NDK 获取(sha256 校验)
scripts/setup.sh --with-libbpf    # liburing 测试所需的一致 libbpf + bpftool
```

## 全量构建

```sh
scripts/build-all.sh              # 本宿主能编的全部 (库, 站点)
scripts/build-all.sh --lib openssl --keep-going
```

`build-all.sh` 驱动 `scripts/ci/build-test.sh`——与 CI 完全相同的代码路径:
本地跑一次和 CI 跑一个任务就是同一个程序。

## 故障排查

| 症状 | 处理 |
| --- | --- |
| `missing 'qemu-aarch64'` | `scripts/setup.sh --with-cross` |
| `Android NDK (r27c) not found` | `scripts/setup.sh --with-android`,或导出 `ANDROID_NDK=<根目录>` |
| liburing 测试的 BPF 探针编译失败 | `scripts/setup.sh --with-libbpf`(一致的 libbpf + bpftool 配对) |
| Windows:`cl.exe not in PATH` | 经 `scripts/build.ps1` 运行(负责加载 Visual Studio 环境) |
| Windows:NASM/Perl 下载停滞 | 直接重跑——下载支持断点续传(`curl -C -`);手动安装亦可 |
| WSL 构建慢但能成 | `/mnt/*` 属正常现象;bst 已把构建树重定向到 ext4(可用 `BST_BUILD` 覆盖) |
| `sha256 mismatch` | 缓存包损坏:删掉 `.cache/src/` 里的对应文件重跑;若上游重发过文件,用 `scripts/pin.sh` 重新固定 |
