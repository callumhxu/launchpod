#include <stdint.h>
#include <string.h>

static double LPDecode(uint64_t encoded, uint64_t mask) {
    uint64_t bits = encoded ^ mask;
    double value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

// Only Classical animation scalars cross this boundary. The Swift presentation code owns the
// Core Animation objects and chooses when to sample these values.
__attribute__((visibility("hidden"), noinline))
double LPClassicalAnimationScalar(uint32_t parameter) {
    volatile uint64_t runtimeMask = 0xa9d74e67c28b513fULL;
    uint64_t mask = runtimeMask;
    switch (parameter) {
        case 1: return LPDecode(0x962782ab0e479df2ULL, mask);
        case 2: return LPDecode(0xe9d74e67c28b513fULL, mask);
        case 3: return LPDecode(0xa9d74e67c28b513fULL, mask);
        case 4: return LPDecode(0x96274e67c28b513fULL, mask);
        case 5: return LPDecode(0x96274e67c28b513fULL, mask);
        case 6: return LPDecode(0xe9d74e67c28b513fULL, mask);
        case 7: return LPDecode(0xe9c34e67c28b513fULL, mask);
        case 10: return LPDecode(0x96374e67c28b513fULL, mask);
        case 11: return LPDecode(0x9601be57bda89db1ULL, mask);
        case 12: return LPDecode(0x962749af89d69d5bULL, mask);
        case 13: return LPDecode(0xe9df4e67c28b513fULL, mask);
        case 14: return LPDecode(0xe9be4e67c28b513fULL, mask);
        case 15: return LPDecode(0x96074e67c28b513fULL, mask);
        case 16: return LPDecode(0xe9d74e67c28b513fULL, mask);
        case 17: return LPDecode(0x96647d54f1b8620cULL, mask);
        case 18: return LPDecode(0x960f4e67c28b513fULL, mask);
        case 19: return LPDecode(0xe9c34e67c28b513fULL, mask);
        case 20: return LPDecode(0xe9c34e67c28b513fULL, mask);
        case 21: return LPDecode(0x96392801a4ed3759ULL, mask);
        case 22: return LPDecode(0x966ed7fe5b12c8a5ULL, mask);
        case 23: return LPDecode(0x96074e67c28b513fULL, mask);
        case 24: return LPDecode(0x963f4e67c28b513fULL, mask);
        case 25: return LPDecode(0x96374e67c28b513fULL, mask);
        case 26: return LPDecode(0xa9d74e67c28b513fULL, mask);
        case 30: return LPDecode(0x96074e67c28b513fULL, mask);
        case 31: return LPDecode(0x967ed7fe5b12c8a5ULL, mask);
        case 32: return LPDecode(0x96754360944794b5ULL, mask);
        case 33: return LPDecode(0x96274e67c28b513fULL, mask);
        case 34: return LPDecode(0xe9c34e67c28b513fULL, mask);
        case 35: return LPDecode(0xe9580e67c28b513fULL, mask);
        case 36: return LPDecode(0x961ed7fe428b513fULL, mask);
        case 37: return LPDecode(0x96274e67c28b513fULL, mask);
        case 38: return LPDecode(0xe9d74e67c28b513fULL, mask);
        case 39: return LPDecode(0x96074e67c28b513fULL, mask);
        case 40: return LPDecode(0xe9df4e67c28b513fULL, mask);
        case 41: return LPDecode(0xe8b45cb7c28b513fULL, mask);
        case 42: return LPDecode(0x963f4e67c28b513fULL, mask);
        case 43: return LPDecode(0x96147d54f1b8620cULL, mask);
        case 44: return LPDecode(0x963f4e67c28b513fULL, mask);
        case 45: return LPDecode(0x96274e67c28b513fULL, mask);
        case 46: return LPDecode(0xe9c34e67c28b513fULL, mask);
        case 47: return LPDecode(0x9626d7fe5b12c8a5ULL, mask);
        case 48: return LPDecode(0x960ed7fe5b12c8a5ULL, mask);
        case 49: return LPDecode(0x966b669200040d16ULL, mask);
        case 50: return LPDecode(0x9636d7fe5b12c8a5ULL, mask);
        case 51: return LPDecode(0x963382ab0e479df2ULL, mask);
        case 52: return LPDecode(0xe9d74e67c28b513fULL, mask);
        case 53: return LPDecode(0x966ed7fe5b12c8a5ULL, mask);
        case 54: return LPDecode(0x966ed7fe5b12c8a5ULL, mask);
        case 55: return LPDecode(0x96374e67c28b513fULL, mask);
        case 56: return LPDecode(0x96312801a4ed3759ULL, mask);
        case 57: return LPDecode(0x963f4e67c28b513fULL, mask);
        case 58: return LPDecode(0xe9db4e67c28b513fULL, mask);
        case 59: return LPDecode(0xe9d94e67c28b513fULL, mask);
        case 60: return LPDecode(0x960ed7fe5b12c8a5ULL, mask);
        case 61: return LPDecode(0x9626d7fe5b12c8a5ULL, mask);
        case 62: return LPDecode(0x963b82ab0e479df2ULL, mask);
        case 63: return LPDecode(0xe9c34e67c28b513fULL, mask);
        case 70: return LPDecode(0x96074e67c28b513fULL, mask);
        case 71: return LPDecode(0x963b82ab0e479df2ULL, mask);
        case 72: return LPDecode(0x966ed7fe5b12c8a5ULL, mask);
        case 73: return LPDecode(0xe9d74e67c28b513fULL, mask);
        case 74: return LPDecode(0xe9d74e67c28b513fULL, mask);
        case 75: return LPDecode(0xe9c34e67c28b513fULL, mask);
        case 80: return LPDecode(0x96374e67c28b513fULL, mask);
        case 81: return LPDecode(0x966ed7fe5b12c8a5ULL, mask);
        case 82: return LPDecode(0xe9c34e67c28b513fULL, mask);
        case 90: return LPDecode(0x96247d54f1b8620cULL, mask);
        case 91: return LPDecode(0x961b82ab0e479df2ULL, mask);
        case 92: return LPDecode(0xe9df4e67c28b513fULL, mask);
        case 93: return LPDecode(0x96274e67c28b513fULL, mask);
        case 94: return LPDecode(0x16274e67c28b513fULL, mask);
        case 95: return LPDecode(0x16274e67c28b513fULL, mask);
        case 96: return LPDecode(0x96274e67c28b513fULL, mask);
        case 97: return LPDecode(0xe9df4e67c28b513fULL, mask);
        case 98: return LPDecode(0xa9d74e67c28b513fULL, mask);
        case 99: return LPDecode(0x69df4e67c28b513fULL, mask);
        case 100: return LPDecode(0xe9df4e67c28b513fULL, mask);
        case 101: return LPDecode(0x96274e67c28b513fULL, mask);
        case 110: return LPDecode(0xe9df4e67c28b513fULL, mask);
        default: __builtin_trap();
    }
}
