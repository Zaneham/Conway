// strncasecmp_test.c - Test strncasecmp correctness
#include <stdio.h>
#include <strings.h>

int main(void) {
    const char *s1 = "IMPXA1";
    const char s2[8] = {'F', '_', 'E', 'N', 'D', 0, 0, 0};

    printf("Testing strncasecmp:\n");
    printf("  s1 = '%s' (bytes: %02X %02X %02X %02X %02X %02X)\n",
           s1, s1[0], s1[1], s1[2], s1[3], s1[4], s1[5]);
    printf("  s2 = '%s' (bytes: %02X %02X %02X %02X %02X %02X)\n",
           s2, s2[0], s2[1], s2[2], s2[3], s2[4], s2[5]);

    int result = strncasecmp(s2, s1, 8);
    printf("  strncasecmp(s2, s1, 8) = %d\n", result);

    if (result == 0) {
        printf("FAIL: strings matched but should not\n");
        return 1;
    } else {
        printf("PASS: strings correctly did not match\n");
        return 0;
    }
}
