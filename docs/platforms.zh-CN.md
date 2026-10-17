# 支持平台

> 中文 | [English](platforms.md)

权威站点表是 [ci/site-matrix.env](../ci/site-matrix.env);本文解释它。
每个站点 = 一个 `--site` 值 + 一个 GNU triple(同时是 `dist/` 目录名)
+ 一个验证级别。

## 图例

- **原生运行** — 在宿主架构上构建并冒烟;加 `--test` 时还跑上游测试套件。
- **qemu** — 在 Linux 上交叉构建;消费方冒烟测试经 `qemu-user` 带交叉
  sysroot 执行。
- **原生执行** — 32 位产物在 x86_64 宿主上直接运行(内核 ia32 支持)。
- **编译+链接** — 产物与消费方冒烟程序可编译链接;运行需要设备(Android),
  有意不尝试。
- **仅 CI** — 由 GitHub Actions 在原生 OS runner 上构建与测试(macOS)。

## 矩阵

| 站点 | Triple | 所需宿主 | 库 | 验证 |
| --- | --- | --- | --- | --- |
| `linux-x86_64` | `x86_64-unknown-linux-gnu` | Linux/WSL | openssl、jemalloc、liburing | 原生运行+套件 |
| `linux-x86_64-clang` | `x86_64-unknown-linux-gnu` | Linux/WSL | openssl、jemalloc、liburing | 原生运行+套件 |
| `linux-aarch64` | `aarch64-unknown-linux-gnu` | Linux/WSL | openssl、jemalloc、liburing | qemu |
| `linux-armv7` | `arm-linux-gnueabihf` | Linux/WSL | openssl、jemalloc、liburing | qemu |
| `linux-riscv64` | `riscv64-unknown-linux-gnu` | Linux/WSL | openssl、jemalloc、liburing | qemu |
| `linux-ppc64le` | `powerpc64le-unknown-linux-gnu` | Linux/WSL | openssl、jemalloc、liburing | qemu |
| `linux-s390x` | `s390x-unknown-linux-gnu` | Linux/WSL | openssl、jemalloc、liburing | qemu |
| `linux-i686` | `i686-unknown-linux-gnu` | Linux/WSL | openssl、jemalloc、liburing | 原生执行 |
| `windows-msvc-x64` | `x86_64-pc-windows-msvc` | Windows | openssl、jemalloc | 原生运行 |
| `windows-msvc-x86` | `i686-pc-windows-msvc` | Windows | openssl、jemalloc | 原生运行 |
| `windows-msvc-arm64` | `aarch64-pc-windows-msvc` | Windows | openssl | 编译+链接 |
| `macos-arm64` | `arm64-apple-darwin` | macOS | openssl、jemalloc | 原生运行+套件(CI) |
| `macos-x64` | `x86_64-apple-darwin` | macOS | openssl、jemalloc | 原生运行+套件(CI) |
| `android-arm64-v8a` | `aarch64-linux-android` | Linux/WSL | openssl、jemalloc | 编译+链接 |
| `android-armeabi-v7a` | `armv7a-linux-androideabi` | Linux/WSL | openssl、jemalloc | 编译+链接 |
| `android-x86_64` | `x86_64-linux-android` | Linux/WSL | openssl、jemalloc | 编译+链接 |
| `android-x86` | `i686-linux-android` | Linux/WSL | openssl、jemalloc | 编译+链接 |

## 平台说明

### Linux 交叉站点
使用 Ubuntu 交叉工具链(`gcc-<arch>-linux-gnu`、`qemu-user`);
`scripts/setup.sh --with-cross` 一键装齐。消费方冒烟测试经
`qemu-user -L /usr/<triple>` 运行——坏产物不可能蒙混过关。`linux-i686`
直接原生执行(x86_64 内核运行 32 位 ELF),需要 `libc6-dev-i386-cross`
与 `linux-libc-dev-i386-cross`。

### Windows
- MSVC 环境由 `scripts/build.ps1` 加载(需要 Visual Studio 2022 与 C++
  工作负载)。缺 NASM(openssl x64/x86 需要)与 Strawberry Perl 时,自动
  便携式落进 `.cache/tools/`——不需要管理员权限。
- `windows-msvc-arm64`:仅 openssl。jemalloc 的官方 MSVC 工程
  (`msvc/jemalloc_vc2022.sln`)只有 x64/Win32 配置,该站点会明确拒绝
  jemalloc,而不是产出坏东西。
- Windows 构建是原生的(无模拟);冒烟测试直接运行产物。

### macOS
- Apple Silicon 优先:`macos-arm64` 是主站点;`macos-x64` 以
  `-arch x86_64` 构建,在 arm64 宿主上同样可用。
- CI 在 `macos-14` runner 上构建两个站点;本地任何装了 Xcode Command
  Line Tools 的 Mac 均可。

### Android
- NDK r27c(LTS),API 24,由 `scripts/setup-ndk.sh` 拉取并做 sha256 校验。
- 四个 ABI 都会编译、安装并链接消费方冒烟程序;运行需要接入设备/模拟器,
  不在本工具默认门的范围。
- jemalloc 在 Android 上以 `--disable-cxx` 配置(bionic 的
  `malloc_usable_size` 带 `nothrow` 声明,与 jemalloc 的 C++ 运算符重载
  编译单元冲突;C++ 集成在 bionic 上本就多余)。

### liburing
构造上仅限 Linux(io_uring 是 Linux 内核接口)。站点表只在 `linux-*` 站点
列出它;其他请求一律明确报错。

## 版本

| 库 | 默认 | 版本线 | 升级路径 |
| --- | --- | --- | --- |
| openssl | 3.5.9 | LTS(4.0.3 也已固定) | `scripts/pin.sh openssl <版本> --update-default` |
| jemalloc | 5.4.0 | 当前稳定 | `scripts/pin.sh jemalloc <版本> --update-default` |
| liburing | 2.15 | 当前稳定 | `scripts/pin.sh liburing <版本> --update-default` |

每个版本行都携带官方来源 URL 与其 sha256;构建前校验。
