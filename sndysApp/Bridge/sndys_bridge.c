/* sndys_bridge.c — C bridge calling mx-compiled Modula-2 audio libraries.
 *
 * This file is compiled by mx as extra-c, linked alongside the M2 modules.
 * It provides exported C functions that Swift can call via a bridging header.
 *
 * The M2 functions are declared as extern — mx links them from .o files.
 * Symbol names follow mx convention: ModuleName_ProcedureName.
 */

#include "sndys_bridge.h"
#include <stdlib.h>
#include <string.h>

/* ── M2 function declarations ──────────────────────────── */
/* These match the mx-generated symbols from the M2 .mod files. */

/* AudioIO */
extern void AudioIO_ReadAudio(const char *path, void **signal,
                               uint32_t *numSamples, uint32_t *sampleRate,
                               int32_t *ok);
extern void AudioIO_FreeSignal(void **signal, uint32_t numSamples);

/* AudioStats */
typedef struct {
    double rmsLevel, peakLevel, crestFactor, dcOffset;
    double rmsDB, peakDB;
    uint32_t numClipped, numSamples;
    double duration;
} M2StatsResult;
extern void AudioStats_Analyze(const void *signal, uint32_t numSamples,
                                uint32_t sampleRate, M2StatsResult *result);

/* KeyDetect */
extern void KeyDetect_DetectKey(const void *signal, uint32_t numSamples,
                                 uint32_t sampleRate,
                                 char *keyName, double *confidence);

/* ShortFeats */
extern void ShortFeats_ExtractFast(const void *signal, uint32_t numSamples,
                                    uint32_t sampleRate,
                                    double winSize, double winStep,
                                    void **featureMatrix, uint32_t *numFrames,
                                    int32_t *ok);
extern void ShortFeats_FreeFeatures(void **matrix, uint32_t numFrames);
extern void ShortFeats_FeatureName(uint32_t idx, char *name);

/* Beat */
extern void Beat_BeatExtract(const void *featureMatrix,
                              uint32_t numFrames, uint32_t numFeatures,
                              double winStep,
                              double *bpm, double *ratio);

/* Rhythm */
extern double Rhythm_BeatStrength(const void *signal, uint32_t numSamples,
                                   uint32_t sampleRate);

/* Onset */
extern void Onset_DetectOnsets(const void *signal, uint32_t numSamples,
                                uint32_t sampleRate, double sensitivity,
                                double *onsets, uint32_t *numOnsets);

/* Spectro */
extern void Spectro_ComputeSpectrogram(const void *signal, uint32_t numSamples,
                                        uint32_t sampleRate,
                                        double winSize, double winStep,
                                        void **output, uint32_t *numFrames,
                                        uint32_t *numBins);
extern void Spectro_ComputeChromagram(const void *signal, uint32_t numSamples,
                                       uint32_t sampleRate,
                                       double winSize, double winStep,
                                       void **output, uint32_t *numFrames);
extern void Spectro_FreeSpectro(void **output, uint32_t numElements);

/* PitchTrack */
extern void PitchTrack_TrackPitch(const void *signal, uint32_t numSamples,
                                   uint32_t sampleRate, uint32_t smoothWindow,
                                   void **pitches, void **times,
                                   uint32_t *numFrames);
extern void PitchTrack_FreePitch(void **pitches, void **times,
                                  uint32_t numFrames);

/* Chords */
typedef struct {
    char name[16];
    double confidence;
    uint32_t root;
} M2ChordResult;
extern void Chords_DetectChordSequence(const void *chromagram,
                                        uint32_t numFrames,
                                        void **chords, uint32_t *numChords);
extern void Chords_FreeChords(void **chords, uint32_t numChords);

/* NoteTranscribe */
typedef struct {
    double startSec, endSec, pitchHz;
    int32_t midiNote;
    char noteName[8];
} M2NoteEvent;
extern void NoteTranscribe_Transcribe(const void *signal, uint32_t numSamples,
                                       uint32_t sampleRate,
                                       void **notes, uint32_t *numNotes);
extern void NoteTranscribe_FreeNotes(void **notes, uint32_t numNotes);

/* Harmonic */
extern void Harmonic_ComputeHarmonicF0(const void *frame, uint32_t frameLen,
                                        uint32_t sampleRate,
                                        double *harmonicRatio, double *f0);

/* VoiceFeats */
extern void VoiceFeats_ComputeFormants(const void *frame, uint32_t frameLen,
                                        uint32_t sampleRate,
                                        double *f1, double *f2, double *f3);
extern double VoiceFeats_ComputeJitter(const void *pitches, uint32_t numFrames);
extern double VoiceFeats_ComputeShimmer(const void *signal, uint32_t numSamples,
                                         uint32_t sampleRate,
                                         const void *pitches, uint32_t numFrames);
extern double VoiceFeats_ComputeHNR(const void *signal, uint32_t numSamples,
                                     uint32_t sampleRate);

/* ── Bridge implementations ────────────────────────────── */

static const double WIN_SIZE = 0.050;
static const double WIN_STEP = 0.025;

int32_t sndys_read_audio(const char *path, double **signal,
                          uint32_t *numSamples, uint32_t *sampleRate) {
    int32_t ok = 0;
    void *sig = NULL;
    AudioIO_ReadAudio(path, &sig, numSamples, sampleRate, &ok);
    *signal = (double *)sig;
    return ok;
}

void sndys_free_signal(double *signal, uint32_t numSamples) {
    void *p = signal;
    AudioIO_FreeSignal(&p, numSamples);
}

void sndys_analyze_stats(const double *signal, uint32_t numSamples,
                          uint32_t sampleRate, SndysStats *result) {
    M2StatsResult m2r;
    AudioStats_Analyze(signal, numSamples, sampleRate, &m2r);
    result->rmsLevel = m2r.rmsLevel;
    result->peakLevel = m2r.peakLevel;
    result->crestFactor = m2r.crestFactor;
    result->dcOffset = m2r.dcOffset;
    result->rmsDB = m2r.rmsDB;
    result->peakDB = m2r.peakDB;
    result->numClipped = m2r.numClipped;
    result->numSamples = m2r.numSamples;
    result->duration = m2r.duration;
}

void sndys_detect_key(const double *signal, uint32_t numSamples,
                       uint32_t sampleRate,
                       char *keyName, uint32_t keyNameSize,
                       double *confidence) {
    char buf[32];
    memset(buf, 0, sizeof(buf));
    KeyDetect_DetectKey(signal, numSamples, sampleRate, buf, confidence);
    strncpy(keyName, buf, keyNameSize - 1);
    keyName[keyNameSize - 1] = '\0';
}

int32_t sndys_detect_beats(const double *signal, uint32_t numSamples,
                            uint32_t sampleRate,
                            double *bpm, double *confidence) {
    void *feats = NULL;
    uint32_t nf = 0;
    int32_t ok = 0;
    ShortFeats_ExtractFast(signal, numSamples, sampleRate,
                           WIN_SIZE, WIN_STEP, &feats, &nf, &ok);
    if (!ok || nf <= 4) {
        *bpm = 0.0;
        *confidence = 0.0;
        return 0;
    }
    Beat_BeatExtract(feats, nf, 34, WIN_STEP, bpm, confidence);
    ShortFeats_FreeFeatures(&feats, nf);
    return 1;
}

double sndys_beat_strength(const double *signal, uint32_t numSamples,
                            uint32_t sampleRate) {
    return Rhythm_BeatStrength(signal, numSamples, sampleRate);
}

uint32_t sndys_detect_onsets(const double *signal, uint32_t numSamples,
                              uint32_t sampleRate, double sensitivity,
                              double *onsets, uint32_t maxOnsets) {
    uint32_t count = 0;
    Onset_DetectOnsets(signal, numSamples, sampleRate, sensitivity,
                       onsets, &count);
    return count < maxOnsets ? count : maxOnsets;
}

double *sndys_compute_spectrogram(const double *signal, uint32_t numSamples,
                                   uint32_t sampleRate,
                                   uint32_t *numFrames, uint32_t *numBins) {
    void *out = NULL;
    Spectro_ComputeSpectrogram(signal, numSamples, sampleRate,
                                WIN_SIZE, WIN_STEP, &out, numFrames, numBins);
    return (double *)out;
}

void sndys_free_spectro(double *data, uint32_t numElements) {
    void *p = data;
    Spectro_FreeSpectro(&p, numElements);
}

double *sndys_compute_chromagram(const double *signal, uint32_t numSamples,
                                  uint32_t sampleRate,
                                  uint32_t *numFrames) {
    void *out = NULL;
    Spectro_ComputeChromagram(signal, numSamples, sampleRate,
                               WIN_SIZE, WIN_STEP, &out, numFrames);
    return (double *)out;
}

void sndys_free_chroma(double *data, uint32_t numFrames) {
    void *p = data;
    Spectro_FreeSpectro(&p, numFrames * 12);
}

double *sndys_track_pitch(const double *signal, uint32_t numSamples,
                           uint32_t sampleRate, uint32_t *numFrames) {
    void *pitches = NULL, *times = NULL;
    TrackPitch_TrackPitch(signal, numSamples, sampleRate, 5,
                           &pitches, &times, numFrames);
    /* Free times, keep pitches */
    if (times) {
        void *t = times;
        /* We can't partially free — return both via pitch ptr.
           Caller uses sndys_free_pitch with both. */
    }
    return (double *)pitches;
}

void sndys_free_pitch(double *pitches, double *times, uint32_t numFrames) {
    void *p = pitches, *t = times;
    PitchTrack_FreePitch(&p, &t, numFrames);
}

SndysChord *sndys_detect_chords(const double *signal, uint32_t numSamples,
                                 uint32_t sampleRate,
                                 uint32_t *numChords) {
    /* Need chromagram first */
    void *chroma = NULL;
    uint32_t chromaFrames = 0;
    void *chords = NULL;

    Spectro_ComputeChromagram(signal, numSamples, sampleRate,
                               WIN_SIZE, WIN_STEP, &chroma, &chromaFrames);
    if (chromaFrames == 0) {
        *numChords = 0;
        return NULL;
    }

    Chords_DetectChordSequence(chroma, chromaFrames, &chords, numChords);
    Spectro_FreeSpectro(&chroma, chromaFrames * 12);
    return (SndysChord *)chords;
}

void sndys_free_chords(SndysChord *chords, uint32_t numChords) {
    void *p = chords;
    Chords_FreeChords(&p, numChords);
}

SndysNote *sndys_transcribe(const double *signal, uint32_t numSamples,
                              uint32_t sampleRate, uint32_t *numNotes) {
    void *notes = NULL;
    NoteTranscribe_Transcribe(signal, numSamples, sampleRate,
                               &notes, numNotes);
    return (SndysNote *)notes;
}

void sndys_free_notes(SndysNote *notes, uint32_t numNotes) {
    void *p = notes;
    NoteTranscribe_FreeNotes(&p, numNotes);
}

void sndys_voice_features(const double *signal, uint32_t numSamples,
                            uint32_t sampleRate,
                            const double *pitches, uint32_t numPitchFrames,
                            SndysVoice *result) {
    uint32_t winSamp = (uint32_t)(WIN_SIZE * sampleRate);
    if (numSamples < winSamp) {
        memset(result, 0, sizeof(*result));
        return;
    }
    VoiceFeats_ComputeFormants(signal, winSamp, sampleRate,
                                &result->f1, &result->f2, &result->f3);
    if (pitches && numPitchFrames >= 2) {
        result->jitter = VoiceFeats_ComputeJitter(pitches, numPitchFrames);
        result->shimmer = VoiceFeats_ComputeShimmer(signal, numSamples,
                                                      sampleRate,
                                                      pitches, numPitchFrames);
    } else {
        result->jitter = 0.0;
        result->shimmer = 0.0;
    }
    result->hnr = VoiceFeats_ComputeHNR(signal, numSamples, sampleRate);
}

void sndys_harmonic(const double *signal, uint32_t frameLen,
                     uint32_t sampleRate,
                     double *harmonicRatio, double *f0) {
    Harmonic_ComputeHarmonicF0(signal, frameLen, sampleRate,
                                harmonicRatio, f0);
}

double *sndys_extract_features(const double *signal, uint32_t numSamples,
                                uint32_t sampleRate,
                                uint32_t *numFrames) {
    void *feats = NULL;
    int32_t ok = 0;
    ShortFeats_ExtractFast(signal, numSamples, sampleRate,
                           WIN_SIZE, WIN_STEP, &feats, numFrames, &ok);
    if (!ok) { *numFrames = 0; return NULL; }
    return (double *)feats;
}

void sndys_free_features(double *feats, uint32_t numFrames) {
    void *p = feats;
    ShortFeats_FreeFeatures(&p, numFrames);
}

static char g_feat_name_buf[64];

const char *sndys_feature_name(uint32_t idx) {
    memset(g_feat_name_buf, 0, sizeof(g_feat_name_buf));
    ShortFeats_FeatureName(idx, g_feat_name_buf);
    return g_feat_name_buf;
}
