/* Stub for RNNoise 0.2's NEON path (header missing from the release tarball). */
#ifndef OS_SUPPORT_H
#define OS_SUPPORT_H
#include <string.h>
#include "common.h"
#ifndef OPUS_CLEAR
#define OPUS_CLEAR(dst, n) (memset((dst), 0, (n)*sizeof(*(dst))))
#endif
#ifndef OPUS_COPY
#define OPUS_COPY(dst, src, n) (memcpy((dst), (src), (n)*sizeof(*(dst))))
#endif
#endif
