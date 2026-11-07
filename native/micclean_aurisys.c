/*
 * MicClean Aurisys shim. MediaTek's audio HAL runs VoIP mic audio through "Aurisys" plugin
 * libraries (ARSI API) instead of Android effects. This library stands in for MediaTek's own
 * speech-enhancement plugin (lib_speech_enh.so): it loads the real one, hands its function table
 * to the HAL unchanged, except that the uplink process call is wrapped so RNNoise runs on
 * MediaTek's output (VoIP uplink: 16 kHz, 16-bit, mono, 20 ms per call).
 */
#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include <pthread.h>
#include <android/log.h>
#include "rnnoise.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "MicCleanAurisys", __VA_ARGS__)
#ifdef __LP64__
#define ORIG_LIB "/vendor/lib64/lib_speech_enh.so"
#else
#define ORIG_LIB "/vendor/lib/lib_speech_enh.so"
#endif

/* data_buf_t at the start of audio_buf_t: memory_size, data_size, p_buffer (from the ARSI demo lib) */
typedef struct { uint32_t memory_size; uint32_t data_size; void *p_buffer; } data_buf_t;

typedef int (*ul_fn)(void *in, void *out, void *ref, void *dbg, void *handler);
typedef void (*assign_fn)(void *lib_fp);
typedef int (*destroy_fn)(void *handler);

static ul_fn g_orig_ul;
static destroy_fn g_orig_destroy;

/* ---- RNNoise state per ARSI handler, 16 kHz path ---- */
#define RNN_N 480
#define SR_N 160                      /* 10 ms at 16 kHz */
typedef struct st_s {
    void *handler; DenoiseState *st;
    float in[SR_N], out[SR_N], up[RNN_N], den[RNN_N], prev_in;
    int in_len, hold, hold_frames, gate_on;
    float vad_thr, floor_gain, gain, atk, rel;
    struct st_s *next;
} st_t;
static st_t *g_states;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

static void conf(st_t *s) {
    int strength = 2;
    FILE *f = fopen("/vendor/etc/micclean_rnnoise.conf", "r");
    if (f) { char l[64]; while (fgets(l, sizeof l, f)) sscanf(l, "strength=%d", &strength); fclose(f); }
    if (strength < 0) strength = 0;
    if (strength > 3) strength = 3;
    static const float thr[4] = {0.f, 0.35f, 0.50f, 0.65f};
    static const float depth[4] = {0.f, -12.f, -25.f, -45.f};
    static const int hold_ms[4] = {0, 300, 220, 150};
    s->gate_on = strength > 0; s->vad_thr = thr[strength];
    s->floor_gain = powf(10.f, depth[strength] / 20.f); s->hold_frames = hold_ms[strength] / 10;
    s->atk = 1.0f - expf(-1.0f / (0.003f * 16000)); s->rel = 1.0f - expf(-1.0f / (0.080f * 16000));
    LOGI("RNNoise on VoIP uplink, strength %d", strength);
}

static st_t *get_state(void *h) {
    pthread_mutex_lock(&g_lock);
    st_t *s = g_states;
    while (s && s->handler != h) s = s->next;
    if (!s && (s = calloc(1, sizeof *s))) {
        s->handler = h; s->st = rnnoise_create(NULL); s->gain = 1.f; conf(s);
        s->next = g_states; g_states = s;
    }
    pthread_mutex_unlock(&g_lock);
    return s;
}

static void frame(st_t *s) {               /* 10 ms: upsample x3, denoise, decimate /3, gate */
    for (int i = 0; i < RNN_N; i++) {
        float pos = (i + 1) / 3.0f - 1.0f; int j = (int)floorf(pos); float t = pos - j;
        float a = j < 0 ? s->prev_in : s->in[j], b = s->in[j + 1 < SR_N ? j + 1 : SR_N - 1];
        s->up[i] = a + (b - a) * t;
    }
    s->prev_in = s->in[SR_N - 1];
    float vad = rnnoise_process_frame(s->st, s->den, s->up);
    for (int i = 0; i < SR_N; i++) s->out[i] = (s->den[3 * i] + s->den[3 * i + 1] + s->den[3 * i + 2]) / 3.0f;
    if (s->gate_on) {
        float target;
        if (vad >= s->vad_thr) { s->hold = s->hold_frames; target = 1.f; }
        else if (s->hold > 0) { s->hold--; target = 1.f; }
        else target = s->floor_gain;
        for (int i = 0; i < SR_N; i++) { s->gain += (target - s->gain) * (target > s->gain ? s->atk : s->rel); s->out[i] *= s->gain; }
    }
}

static int my_ul(void *in, void *out, void *ref, void *dbg, void *handler) {
    int r = g_orig_ul(in, out, ref, dbg, handler);
    data_buf_t *o = (data_buf_t *)out;
    if (r != 0 || !o || !o->p_buffer || o->data_size == 0 || (o->data_size & 1)) return r;
    st_t *s = get_state(handler);
    if (!s || !s->st) return r;
    int16_t *p = (int16_t *)o->p_buffer;
    uint32_t n = o->data_size / 2;
    for (uint32_t i = 0; i < n; i++) {     /* fixed 10 ms delay, sample in -> sample out */
        float v = s->out[s->in_len];
        s->in[s->in_len++] = p[i];
        if (s->in_len == SR_N) { frame(s); s->in_len = 0; }
        if (v > 32767.f) v = 32767.f;
        if (v < -32768.f) v = -32768.f;
        p[i] = (int16_t)lrintf(v);
    }
    return r;
}

static int my_destroy(void *handler) {
    pthread_mutex_lock(&g_lock);
    for (st_t **pp = &g_states; *pp; pp = &(*pp)->next)
        if ((*pp)->handler == handler) { st_t *d = *pp; *pp = d->next; rnnoise_destroy(d->st); free(d); break; }
    pthread_mutex_unlock(&g_lock);
    return g_orig_destroy(handler);
}

__attribute__((visibility("default")))
void dynamic_link_arsi_assign_lib_fp(void *lib_fp) {
    void *h = dlopen(ORIG_LIB, RTLD_NOW);
    assign_fn assign = h ? (assign_fn)dlsym(h, "dynamic_link_arsi_assign_lib_fp") : NULL;
    if (!assign) { LOGI("cannot load %s", ORIG_LIB); return; }
    assign(lib_fp);
    void *ul = dlsym(h, "mtk_arsi_process_ul_buf"), *ds = dlsym(h, "mtk_arsi_destroy_handler");
    void **slot = (void **)lib_fp;
    int hooked = 0;
    for (int i = 0; i < 64; i++) {          /* swap our wrappers into the slots the real lib filled */
        if (ul && slot[i] == ul) { g_orig_ul = (ul_fn)ul; slot[i] = (void *)my_ul; hooked |= 1; }
        else if (ds && slot[i] == ds) { g_orig_destroy = (destroy_fn)ds; slot[i] = (void *)my_destroy; hooked |= 2; }
    }
    LOGI("hooked uplink=%d destroy=%d", hooked & 1, (hooked >> 1) & 1);
}
