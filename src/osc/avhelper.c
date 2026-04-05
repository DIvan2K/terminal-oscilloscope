/* Minimal libav audio capture without requiring dev headers.
   Loads libavformat/libavdevice at runtime via dlopen. */

#include <dlfcn.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

/* Opaque handles — we never touch the struct internals from Nim */
typedef void AVFormatContext;
typedef void AVInputFormat;
typedef void AVDictionary;

/* AVPacket — we only need data, size, stream_index.
   Layout is stable across FFmpeg 5.x/6.x/7.x:
   first field is AVBufferRef*, then data, size, stream_index */
typedef struct {
    void *buf;
    uint8_t *data;
    int size;
    int stream_index;
    /* we don't care about the rest */
} AVPacketHead;

/* Function pointer types matching libav API */
typedef void (*fn_avdevice_register_all)(void);
typedef const AVInputFormat* (*fn_av_find_input_format)(const char*);
typedef int (*fn_avformat_open_input)(AVFormatContext**, const char*,
    const AVInputFormat*, AVDictionary**);
typedef int (*fn_avformat_find_stream_info)(AVFormatContext*, AVDictionary**);
typedef void (*fn_avformat_close_input)(AVFormatContext**);
typedef int (*fn_av_read_frame)(AVFormatContext*, AVPacketHead*);
typedef AVPacketHead* (*fn_av_packet_alloc)(void);
typedef void (*fn_av_packet_free)(AVPacketHead**);
typedef void (*fn_av_packet_unref)(AVPacketHead*);

/* Accessors for AVFormatContext fields via known offsets.
   We use av_find_best_stream to avoid struct access entirely. */
typedef int (*fn_av_find_best_stream)(AVFormatContext*, int media_type,
    int wanted, int related, void**, int flags);

/* Loaded function pointers */
static fn_avdevice_register_all p_avdevice_register_all;
static fn_av_find_input_format p_av_find_input_format;
static fn_avformat_open_input p_avformat_open_input;
static fn_avformat_find_stream_info p_avformat_find_stream_info;
static fn_avformat_close_input p_avformat_close_input;
static fn_av_read_frame p_av_read_frame;
static fn_av_packet_alloc p_av_packet_alloc;
static fn_av_packet_free p_av_packet_free;
static fn_av_packet_unref p_av_packet_unref;
static fn_av_find_best_stream p_av_find_best_stream;

static void *h_format, *h_device, *h_util;
static int loaded = 0;

static int load_libs(void) {
    if (loaded) return loaded > 0 ? 0 : -1;

    h_format = dlopen("libavformat.so", RTLD_LAZY);
    if (!h_format) h_format = dlopen("libavformat.so.60", RTLD_LAZY);
    if (!h_format) h_format = dlopen("libavformat.so.59", RTLD_LAZY);

    h_device = dlopen("libavdevice.so", RTLD_LAZY);
    if (!h_device) h_device = dlopen("libavdevice.so.60", RTLD_LAZY);
    if (!h_device) h_device = dlopen("libavdevice.so.59", RTLD_LAZY);

    if (!h_format || !h_device) { loaded = -1; return -1; }

    p_avdevice_register_all = (fn_avdevice_register_all)
        dlsym(h_device, "avdevice_register_all");
    p_av_find_input_format = (fn_av_find_input_format)
        dlsym(h_format, "av_find_input_format");
    p_avformat_open_input = (fn_avformat_open_input)
        dlsym(h_format, "avformat_open_input");
    p_avformat_find_stream_info = (fn_avformat_find_stream_info)
        dlsym(h_format, "avformat_find_stream_info");
    p_avformat_close_input = (fn_avformat_close_input)
        dlsym(h_format, "avformat_close_input");
    p_av_read_frame = (fn_av_read_frame)
        dlsym(h_format, "av_read_frame");
    p_av_find_best_stream = (fn_av_find_best_stream)
        dlsym(h_format, "av_find_best_stream");
    p_av_packet_alloc = (fn_av_packet_alloc)
        dlsym(h_format, "av_packet_alloc");
    if (!p_av_packet_alloc) {
        h_util = dlopen("libavcodec.so", RTLD_LAZY);
        if (!h_util) h_util = dlopen("libavcodec.so.60", RTLD_LAZY);
        if (h_util) p_av_packet_alloc = (fn_av_packet_alloc)
            dlsym(h_util, "av_packet_alloc");
    }
    p_av_packet_free = (fn_av_packet_free)
        dlsym(h_format, "av_packet_free");
    if (!p_av_packet_free && h_util)
        p_av_packet_free = (fn_av_packet_free)dlsym(h_util, "av_packet_free");
    p_av_packet_unref = (fn_av_packet_unref)
        dlsym(h_format, "av_packet_unref");
    if (!p_av_packet_unref && h_util)
        p_av_packet_unref = (fn_av_packet_unref)dlsym(h_util, "av_packet_unref");

    if (!p_avformat_open_input || !p_av_read_frame ||
        !p_av_packet_alloc || !p_av_packet_free) {
        loaded = -1;
        return -1;
    }

    loaded = 1;
    return 0;
}

/* ── Public API called from Nim ──────────────────────────────── */

int av_helper_init(void) {
    if (load_libs() < 0) return -1;
    if (p_avdevice_register_all) p_avdevice_register_all();
    return 0;
}

int av_helper_open_pulse(AVFormatContext **ctx, const char *device) {
    if (!p_av_find_input_format || !p_avformat_open_input) return -1;
    const AVInputFormat *fmt = p_av_find_input_format("pulse");
    if (!fmt) return -1;
    return p_avformat_open_input(ctx, device, fmt, NULL);
}

int av_helper_find_audio_stream(AVFormatContext *ctx) {
    if (!p_av_find_best_stream) return 0; /* assume stream 0 */
    int ret = p_av_find_best_stream(ctx, 1 /* AVMEDIA_TYPE_AUDIO */,
                                     -1, -1, NULL, 0);
    return ret >= 0 ? ret : 0;
}

int av_helper_find_stream_info(AVFormatContext *ctx) {
    if (!p_avformat_find_stream_info) return 0;
    return p_avformat_find_stream_info(ctx, NULL);
}

int av_helper_read_frame(AVFormatContext *ctx, AVPacketHead *pkt) {
    return p_av_read_frame(ctx, pkt);
}

int av_helper_packet_stream(AVPacketHead *pkt) { return pkt->stream_index; }
uint8_t* av_helper_packet_data(AVPacketHead *pkt) { return pkt->data; }
int av_helper_packet_size(AVPacketHead *pkt) { return pkt->size; }

AVPacketHead* av_helper_packet_alloc(void) { return p_av_packet_alloc(); }
void av_helper_packet_unref(AVPacketHead *pkt) { if (p_av_packet_unref) p_av_packet_unref(pkt); }
void av_helper_packet_free(AVPacketHead **pkt) { if (p_av_packet_free) p_av_packet_free(pkt); }

void av_helper_close(AVFormatContext **ctx) {
    if (p_avformat_close_input) p_avformat_close_input(ctx);
}
