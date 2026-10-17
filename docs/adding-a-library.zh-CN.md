# 向 bst 添加新库

> 中文 | [English](adding-a-library.md)

给 bst 加一个"难编译库"是一张清单:一个配方文件、两张表的行、一个冒烟测试、
CI 矩阵行与文档更新。框架(入口、站点解析、下载校验、暂存、日志)已经就位。

## 配方契约

每个库住在 `scripts/lib/recipes/<库>.sh`,实现至多五个函数。框架按顺序调用;
每个函数运行时,站点上下文都已解析完毕。

| 函数 | 必需 | 职责 |
| --- | --- | --- |
| `recipe_configure` | 是 | 按 `$BST_VARIANT` 跑上游 configure |
| `recipe_build` | 是 | 编译 |
| `recipe_install` | 是 | 安装进 `$BST_DIST`(暂存前缀) |
| `recipe_test` | 否 | 上游测试套件(仅 `--test` 时调用) |
| `recipe_smoke` | 建议 | 针对 `$BST_DIST` 编译+链接+运行消费方冒烟 |

### 可用变量

| 变量 | 含义 |
| --- | --- |
| `BST_SRC` | 已解压(且已打补丁)的上游源码树 |
| `BST_BUILD_DIR` | 本形态的构建目录(`--clean` 会清掉) |
| `BST_DIST` | 正在产出的暂存前缀(`dist/<库>/<triple>`) |
| `BST_VARIANT` | `static` 或 `shared` |
| `BST_JOBS` | 并行度 |
| `BST_TEST` | 请求了 `--test` 时为 `1` |
| `SITE`、`SITE_TRIPLE`、`SITE_FAMILY`、`SITE_CROSS`、`SITE_EMU` | 站点行事实 |
| `CC`、`CXX`、`AR`、`RANLIB`、`STRIP` | 站点工具链 |
| `SITE_SYSROOT` | 交叉 sysroot(原生站点为空) |

### 可用助手(scripts/lib/common.sh)

| 助手 | 用途 |
| --- | --- |
| `bst_die "$msg"` / `bst_warn` / `bst_info` | 失败即停 / 警告 / 日志 |
| `bst_require_cmd <命令> <安装提示>` | 可操作的前置检查 |
| `bst_run_exe <可执行文件>` | 交叉站点经 `qemu-user -L $SITE_SYSROOT` 运行 |
| `bst_win_path <路径>` | MSVC 工具用 Windows 路径,其余平台原样 |
| `bst_ndk_root` | 校验过的 NDK 根(环境变量 `ANDROID_NDK` 或已拉取副本) |
| `site_is_cross` | 交叉站点为真 |
| `bst_prepare_stage` / `bst_list_dist` | 框架自身使用 |

## 清单

1. **配方**:新建 `scripts/lib/recipes/<库>.sh`。平台需要不同处理时按
   `$SITE_FAMILY` 分支(参考 `openssl.sh` 的 Configure 目标表、
   `jemalloc.sh` 的 autotools/MSVC 双路、`liburing.sh` 的仅 Linux 形态)。
2. **站点表**:在 `ci/site-matrix.env` 中把库名加进上游支持的每个站点的
   `libs` 列。不支持的组合保持缺席——入口会明确拒绝并给出提示。
3. **版本**:`scripts/pin.sh <库> <版本> --update-default` 追加来源行
   (URL + sha256)并设定默认版本。若 `pin.sh` 未设置,补上
   `_DEFAULT_VERSION` 行。
4. **冒烟测试**:`tests/smoke/<库>_smoke.c`——一个链接暂存产物、
   证明库确实可用的小程序(如 openssl 的已知答案摘要)。
   在 `recipe_smoke` 中调用。
5. **CI 矩阵**:在 `.github/workflows/ci.yml` 与 `release.yml` 中为新库
   加行(矩阵有意手写;`ci/check-workflows.sh` 会在与站点表漂移时失败)。
6. **文档**:把库加进 README 表、`docs/building.md` 的测试表、
   `docs/platforms.md` 的矩阵(以及对应的 `.zh-CN.md` 镜像)。
7. **验证**:`scripts/tests/unit.sh`,然后原生 `--test` 构建一次、
   交叉构建一次(冒烟经 qemu 运行),再推送交给 CI。

## 最小骨架

```bash
# shellcheck shell=bash
# mylib 配方。

recipe_configure() {
    case "$SITE_FAMILY" in
        windows) bst_die "mylib: MSVC support not wired yet" ;;
    esac
    local args=(--prefix="$BST_DIST")
    case "$BST_VARIANT" in
        static) args+=(--disable-shared) ;;
        shared) args+=(--enable-shared) ;;
    esac
    site_is_cross && args+=(--host="$SITE_TRIPLE")
    ( cd "$BST_BUILD_DIR" && CC="$CC" "$BST_SRC/configure" "${args[@]}" ) \
        || bst_die "mylib configure failed"
}

recipe_build() {
    ( cd "$BST_BUILD_DIR" && make -j"$BST_JOBS" ) || bst_die "mylib build failed"
}

recipe_install() {
    ( cd "$BST_BUILD_DIR" && make install ) || bst_die "mylib install failed"
}

recipe_smoke() {
    local exe="$BST_BUILD_DIR/smoke-mylib"
    "$CC" -I"$BST_DIST/include" "$BST_ROOT/tests/smoke/mylib_smoke.c" \
        "$BST_DIST/lib/libmylib.a" -o "$exe" || bst_die "mylib smoke link failed"
    bst_run_exe "$exe" || bst_die "mylib smoke run failed"
}
```

## 保持可靠的红线

- 失败即停:任何意外状态都 `bst_die`,绝不静默跳过。
- 绝不改测试掩盖失败;补丁只改构建行为(见 `patches/README.md`)。
- 站点表是唯一事实来源;不要在配方里发明站点键。
- 冒烟测试是与消费方的契约:它必须按文档教用户的方式链接。
