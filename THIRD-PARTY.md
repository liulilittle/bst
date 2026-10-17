# Third-party components

bst itself is MIT-licensed (see [LICENSE](LICENSE)). The scripts download,
build and stage **unmodified upstream** releases. Nothing from the
libraries below is vendored or committed to this repository; the pinned
tarballs are fetched from their official sources and verified against the
sha256 values recorded in [ci/versions.env](ci/versions.env).

| Component | License | Source |
| --- | --- | --- |
| OpenSSL | Apache License 2.0 | https://github.com/openssl/openssl (LICENSE.txt in the tarball) |
| jemalloc | BSD 2-Clause | https://github.com/jemalloc/jemalloc (COPYING in the tarball) |
| liburing | MIT | https://github.com/axboe/liburing (COPYING in the tarball) |
| Android NDK (downloaded by scripts/setup-ndk.sh) | Google's NDK license | https://developer.android.com/ndk |

Anything you drop into [`patches/`](patches/) is applied on top of the
upstream tarball at build time and keeps the upstream license of the file
it touches. Patches are never applied to released artifacts silently: the
applied patch set is stamped into the build tree and recorded in the
staged `BUILD-INFO.txt` chain (the source tarball sha256 is always listed).
