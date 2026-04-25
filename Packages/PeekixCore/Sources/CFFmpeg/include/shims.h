#ifndef CFFMPEG_SHIMS_H
#define CFFMPEG_SHIMS_H

#include <errno.h>
#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavutil/avutil.h"
#include "libavutil/imgutils.h"
#include "libavutil/pixdesc.h"

// Macros that the Swift importer cannot evaluate are exposed as inline shims.
static inline int64_t cffmpeg_av_nopts_value(void) {
    return AV_NOPTS_VALUE;
}

static inline int cffmpeg_averror_eof(void) {
    return AVERROR_EOF;
}

static inline int cffmpeg_averror_eagain(void) {
    return AVERROR(EAGAIN);
}

#endif /* CFFMPEG_SHIMS_H */
