#ifndef CFFMPEG_SHIMS_H
#define CFFMPEG_SHIMS_H

#include <errno.h>
#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavutil/avutil.h"
#include "libavutil/imgutils.h"
#include "libavutil/pixdesc.h"
#include "libavutil/channel_layout.h"
#include "libswresample/swresample.h"

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

// Audio helpers ---------------------------------------------------------

static inline int cffmpeg_codec_ctx_channels(const AVCodecContext *ctx) {
    return ctx->ch_layout.nb_channels;
}

static inline int cffmpeg_codec_ctx_sample_rate(const AVCodecContext *ctx) {
    return ctx->sample_rate;
}

static inline int cffmpeg_codec_ctx_sample_fmt(const AVCodecContext *ctx) {
    return (int)ctx->sample_fmt;
}

// Configure & initialize a SwrContext that converts the decoder's native
// audio format to interleaved float32 at out_sample_rate, preserving channels.
static inline int cffmpeg_swr_setup_for_decoder(struct SwrContext **swr,
                                                const AVCodecContext *ctx,
                                                int out_sample_rate,
                                                int out_nb_channels,
                                                int out_sample_fmt) {
    if (!swr || !ctx) return -1;
    if (*swr) {
        swr_free(swr);
    }
    AVChannelLayout out_layout;
    memset(&out_layout, 0, sizeof(out_layout));
    av_channel_layout_default(&out_layout, out_nb_channels > 0 ? out_nb_channels : 2);

    int ret = swr_alloc_set_opts2(swr,
                                  &out_layout,
                                  (enum AVSampleFormat)out_sample_fmt,
                                  out_sample_rate,
                                  &ctx->ch_layout,
                                  ctx->sample_fmt,
                                  ctx->sample_rate,
                                  0, NULL);
    av_channel_layout_uninit(&out_layout);
    if (ret < 0 || !*swr) return ret;
    return swr_init(*swr);
}

static inline int cffmpeg_swr_convert_to_float(struct SwrContext *swr,
                                               uint8_t *const *out_buffers,
                                               int out_count,
                                               const AVFrame *frame) {
    if (!swr || !frame) return -1;
    return swr_convert(swr,
                       out_buffers,
                       out_count,
                       (const uint8_t **)frame->extended_data,
                       frame->nb_samples);
}

static inline int cffmpeg_av_sample_fmt_fltp(void) {
    return (int)AV_SAMPLE_FMT_FLTP;
}

#endif /* CFFMPEG_SHIMS_H */
