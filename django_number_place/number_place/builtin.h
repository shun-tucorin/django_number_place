#if defined(_MSC_VER)
# pragma intrinsic(__popcnt)
# pragma intrinsic(_BitScanForward)

# define __builtin_popcount(v) __popcnt(v)

inline static int __builtin_ctz(int v)
    {
    int r;
    _BitScanForward(&r, v);
    return r;
    }

# include <memory.h>
# define __builtin_alloca(s) _alloca(s)

#endif
