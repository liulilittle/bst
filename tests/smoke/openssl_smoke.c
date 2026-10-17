/* bst smoke test for openssl: link against the staged libraries, run, and
 * verify one known-answer SHA-256 digest. */
#include <stdio.h>
#include <string.h>

#include <openssl/evp.h>
#include <openssl/opensslv.h>

int main(void) {
    static const unsigned char want[32] = {
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad
    };
    unsigned char md[EVP_MAX_MD_SIZE];
    unsigned int len = 0;

    if (EVP_Digest("abc", 3, md, &len, EVP_sha256(), NULL) != 1) {
        fprintf(stderr, "openssl smoke: EVP_Digest failed\n");
        return 10;
    }
    if (len != 32 || memcmp(md, want, 32) != 0) {
        fprintf(stderr, "openssl smoke: sha256(\"abc\") mismatch\n");
        return 11;
    }
    printf("openssl smoke ok: %s\n", OpenSSL_version(OPENSSL_VERSION));
    return 0;
}
