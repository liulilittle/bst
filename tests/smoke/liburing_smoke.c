/* bst smoke test for liburing: link against the staged library, run, and
 * bring up one ring.  When the running kernel (or emulator) cannot provide
 * io_uring the smoke reports SKIP and still exits 0. */
#include <errno.h>
#include <stdio.h>

#include <liburing.h>

int main(void) {
    struct io_uring ring;
    int ret = io_uring_queue_init(8, &ring, 0);

    if (ret < 0) {
        if (ret == -ENOSYS || ret == -EPERM) {
            printf("liburing smoke SKIP: io_uring unavailable on this kernel (%d)\n", ret);
            return 0;
        }
        fprintf(stderr, "liburing smoke: io_uring_queue_init failed: %d\n", ret);
        return 10;
    }
    printf("liburing smoke ok: features=0x%x\n", ring.features);
    io_uring_queue_exit(&ring);
    return 0;
}
