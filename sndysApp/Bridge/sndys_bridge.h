/* sndys_bridge.h — C interface to the sndys audio analysis toolkit.
 *
 * Wraps the Modula-2 m2audio/m2wav/m2fft libraries with a flat C API
 * suitable for calling from Swift via a bridging header.
 *
 * All audio data is LONGREAL (double) arrays.
 * All sizes are in sample frames unless noted.
 * Caller owns input buffers; bridge allocates outputs.
 * Every Alloc-returning function has a matching Free function.
 */

#ifndef SNDYS_BRIDGE_H
#define SNDYS_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Must be called once before any other sndys_* function.
 * Initializes M2 module state (chord templates, key profiles, etc). */
void sndys_init(void);

/* ── Audio I/O ─────────────────────────────────────────── */

/* Read a WAV file, auto-convert stereo to mono.
 * Returns 1 on success, 0 on failure.
 * On success: *signal is a malloc'd double array, *numSamples and
 * *sampleRate are filled in. Caller must call sndys_free_signal(). */
int32_t sndys_read_audio(const char *path,
                          double **signal,
                          uint32_t *numSamples,
                          uint32_t *sampleRate);

void sndys_free_signal(double *signal, uint32_t numSamples);

/* ── Audio Stats ───────────────────────────────────────── */

typedef struct {
    double rmsLevel;
    double peakLevel;
    double crestFactor;
    double dcOffset;
    double rmsDB;
    double peakDB;
    uint32_t numClipped;
    uint32_t numSamples;
    double duration;
} SndysStats;

void sndys_analyze_stats(const double *signal, uint32_t numSamples,
                          uint32_t sampleRate, SndysStats *result);

/* ── Key Detection ─────────────────────────────────────── */

void sndys_detect_key(const double *signal, uint32_t numSamples,
                       uint32_t sampleRate,
                       char *keyName, uint32_t keyNameSize,
                       double *confidence);

/* ── Beat / Tempo ──────────────────────────────────────── */

/* Returns 1 on success, 0 on failure. */
int32_t sndys_detect_beats(const double *signal, uint32_t numSamples,
                            uint32_t sampleRate,
                            double *bpm, double *confidence);

double sndys_beat_strength(const double *signal, uint32_t numSamples,
                            uint32_t sampleRate);

/* ── Onset Detection ───────────────────────────────────── */

/* Fills onsets array (max maxOnsets). Returns actual count. */
uint32_t sndys_detect_onsets(const double *signal, uint32_t numSamples,
                              uint32_t sampleRate, double sensitivity,
                              double *onsets, uint32_t maxOnsets);

/* ── Spectrogram ───────────────────────────────────────── */

/* Returns malloc'd double array (numFrames * numBins).
 * Caller must call sndys_free_spectro(). */
double *sndys_compute_spectrogram(const double *signal, uint32_t numSamples,
                                   uint32_t sampleRate,
                                   uint32_t *numFrames, uint32_t *numBins);

void sndys_free_spectro(double *data, uint32_t numElements);

/* ── Chromagram ────────────────────────────────────────── */

/* Returns malloc'd double array (numFrames * 12).
 * Caller must call sndys_free_chroma(). */
double *sndys_compute_chromagram(const double *signal, uint32_t numSamples,
                                  uint32_t sampleRate,
                                  uint32_t *numFrames);

void sndys_free_chroma(double *data, uint32_t numFrames);

/* ── Pitch Tracking ────────────────────────────────────── */

/* Returns malloc'd pitch and times arrays (numFrames doubles each).
 * pitches: 0.0 = unvoiced.  times: seconds per frame.
 * Caller must call sndys_free_pitch(). */
void sndys_track_pitch(const double *signal, uint32_t numSamples,
                        uint32_t sampleRate,
                        double **pitches, double **times,
                        uint32_t *numFrames);

void sndys_free_pitch(double *pitches, double *times, uint32_t numFrames);

/* ── Chord Detection ───────────────────────────────────── */

typedef struct {
    char name[16];
    double confidence;
    uint32_t root;
} SndysChord;

/* Returns malloc'd chord array. Caller must call sndys_free_chords(). */
SndysChord *sndys_detect_chords(const double *signal, uint32_t numSamples,
                                 uint32_t sampleRate,
                                 uint32_t *numChords);

void sndys_free_chords(SndysChord *chords, uint32_t numChords);

/* ── Note Transcription ────────────────────────────────── */

typedef struct {
    double startSec;
    double endSec;
    double pitchHz;
    int32_t midiNote;
    char noteName[8];
} SndysNote;

SndysNote *sndys_transcribe(const double *signal, uint32_t numSamples,
                              uint32_t sampleRate,
                              uint32_t *numNotes);

void sndys_free_notes(SndysNote *notes, uint32_t numNotes);

/* ── Voice Features ────────────────────────────────────── */

typedef struct {
    double f1, f2, f3;
    double jitter;
    double shimmer;
    double hnr;
} SndysVoice;

void sndys_voice_features(const double *signal, uint32_t numSamples,
                            uint32_t sampleRate,
                            const double *pitches, uint32_t numPitchFrames,
                            SndysVoice *result);

/* ── Harmonic ──────────────────────────────────────────── */

void sndys_harmonic(const double *signal, uint32_t frameLen,
                     uint32_t sampleRate,
                     double *harmonicRatio, double *f0);

/* ── Short-Term Features ───────────────────────────────── */

/* Returns malloc'd array (numFrames * 34 doubles).
 * Caller must call sndys_free_features(). */
double *sndys_extract_features(const double *signal, uint32_t numSamples,
                                uint32_t sampleRate,
                                uint32_t *numFrames);

void sndys_free_features(double *feats, uint32_t numFrames);

/* Get feature name by index (0-33). Returns static string. */
const char *sndys_feature_name(uint32_t idx);

#ifdef __cplusplus
}
#endif

#endif /* SNDYS_BRIDGE_H */
