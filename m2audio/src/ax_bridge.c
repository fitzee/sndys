/* ax_bridge.c — Minimal SDL2 audio bridge for m2audio Playback module.
 *
 * Wraps SDL2 queued audio output with a flat C API that Modula-2 can call
 * via DEFINITION MODULE FOR "C".  All types are scalars or void pointers.
 *
 * SDL_AudioSpec is opaque to M2; we marshal fields through scalar getters
 * after SDL_OpenAudioDevice fills the obtained spec.
 */

#include <SDL2/SDL.h>
#include <stdint.h>

/* ── Cached obtained spec from last successful OpenAudioDevice ─────── */

static SDL_AudioSpec g_obtained;

/* ── Init / Quit ──────────────────────────────────────────────────── */

int32_t ax_init(void) {
    return SDL_InitSubSystem(SDL_INIT_AUDIO) == 0 ? 1 : 0;
}

void ax_quit(void) {
    SDL_QuitSubSystem(SDL_INIT_AUDIO);
}

/* ── Device open / close ──────────────────────────────────────────── */

/* Opens an audio output device for queued playback (no callback).
 * Returns SDL_AudioDeviceID (>= 2 on success, 0 on failure).
 * The obtained spec is cached and queryable via ax_obtained_*().
 *
 * format values (SDL constants):
 *   0x8010 = AUDIO_S16LSB  (signed 16-bit little-endian)
 *   0x8120 = AUDIO_F32LSB  (32-bit float little-endian)
 */
uint32_t ax_open_device(int32_t freq, int32_t channels,
                        int32_t format, int32_t samples) {
    SDL_AudioSpec want;
    SDL_zero(want);
    want.freq     = freq;
    want.format   = (SDL_AudioFormat)format;
    want.channels = (Uint8)channels;
    want.samples  = (Uint16)samples;
    want.callback = NULL;  /* queued mode */

    SDL_zero(g_obtained);
    SDL_AudioDeviceID dev = SDL_OpenAudioDevice(
        NULL, 0, &want, &g_obtained, 0);
    return (uint32_t)dev;
}

void ax_close_device(uint32_t dev) {
    SDL_CloseAudioDevice((SDL_AudioDeviceID)dev);
}

/* ── Playback control ─────────────────────────────────────────────── */

void ax_pause_device(uint32_t dev) {
    SDL_PauseAudioDevice((SDL_AudioDeviceID)dev, 1);
}

void ax_resume_device(uint32_t dev) {
    SDL_PauseAudioDevice((SDL_AudioDeviceID)dev, 0);
}

/* ── Queue operations ─────────────────────────────────────────────── */

int32_t ax_queue_audio(uint32_t dev, const void *data, uint32_t len) {
    return SDL_QueueAudio((SDL_AudioDeviceID)dev, data, len) == 0 ? 1 : 0;
}

uint32_t ax_get_queued_size(uint32_t dev) {
    return SDL_GetQueuedAudioSize((SDL_AudioDeviceID)dev);
}

void ax_clear_queued(uint32_t dev) {
    SDL_ClearQueuedAudio((SDL_AudioDeviceID)dev);
}

/* ── Obtained spec accessors ──────────────────────────────────────── */

int32_t ax_obtained_freq(void)     { return g_obtained.freq; }
int32_t ax_obtained_format(void)   { return (int32_t)g_obtained.format; }
int32_t ax_obtained_channels(void) { return (int32_t)g_obtained.channels; }
int32_t ax_obtained_samples(void)  { return (int32_t)g_obtained.samples; }

/* Bytes per sample frame: channels * bytes_per_sample */
int32_t ax_obtained_frame_size(void) {
    return (int32_t)(g_obtained.channels * SDL_AUDIO_BITSIZE(g_obtained.format) / 8);
}

/* ── Error ────────────────────────────────────────────────────────── */

const char *ax_get_error(void) {
    return SDL_GetError();
}

/* ── Timer (for drain-wait loops) ─────────────────────────────────── */

uint32_t ax_get_ticks(void) {
    return SDL_GetTicks();
}

void ax_delay(uint32_t ms) {
    SDL_Delay(ms);
}

/* ── Terminal raw mode (for keypress detection during playback) ──── */

#include <termios.h>
#include <unistd.h>
#include <sys/select.h>

static struct termios g_orig_termios;
static int g_raw_active = 0;

void ax_terminal_raw(void) {
    struct termios raw;
    if (g_raw_active) return;
    tcgetattr(STDIN_FILENO, &g_orig_termios);
    raw = g_orig_termios;
    raw.c_lflag &= ~(ICANON | ECHO);
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSANOW, &raw);
    g_raw_active = 1;
}

void ax_terminal_restore(void) {
    if (!g_raw_active) return;
    tcsetattr(STDIN_FILENO, TCSANOW, &g_orig_termios);
    g_raw_active = 0;
}

int32_t ax_key_pressed(void) {
    if (!g_raw_active) return 0;
    fd_set fds;
    struct timeval tv = {0, 0};
    FD_ZERO(&fds);
    FD_SET(STDIN_FILENO, &fds);
    if (select(STDIN_FILENO + 1, &fds, NULL, NULL, &tv) > 0) {
        char ch;
        if (read(STDIN_FILENO, &ch, 1) == 1) return 1;
    }
    return 0;
}
