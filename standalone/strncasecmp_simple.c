// strncasecmp_simple.c - Minimal test without printf
#include <strings.h>

int main(void) {
    const char *s1 = "IMPXA1";
    const char s2[8] = {'F', '_', 'E', 'N', 'D', 0, 0, 0};

    int result = strncasecmp(s2, s1, 8);

    // Return 0 if correctly not matching (result != 0)
    // Return 1 if incorrectly matching (result == 0)
    return (result == 0) ? 1 : 0;
}
