// SndysBridge.swift — Swift wrapper around the sndys C bridge.
// Provides type-safe access to all audio analysis functions.

import Foundation

/// Loaded audio signal
class AudioSignal {
    let samples: UnsafeMutablePointer<Double>
    let numSamples: UInt32
    let sampleRate: UInt32

    init(samples: UnsafeMutablePointer<Double>, numSamples: UInt32, sampleRate: UInt32) {
        self.samples = samples
        self.numSamples = numSamples
        self.sampleRate = sampleRate
    }

    deinit {
        sndys_free_signal(samples, numSamples)
    }

    var duration: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(numSamples) / Double(sampleRate)
    }

    static func load(path: String) -> AudioSignal? {
        var signal: UnsafeMutablePointer<Double>?
        var numSamples: UInt32 = 0
        var sampleRate: UInt32 = 0
        let ok = sndys_read_audio(path, &signal, &numSamples, &sampleRate)
        guard ok != 0, let sig = signal, numSamples > 0 else { return nil }
        return AudioSignal(samples: sig, numSamples: numSamples, sampleRate: sampleRate)
    }
}

/// Audio statistics
struct AudioStats {
    let rmsDB: Double
    let peakDB: Double
    let crestFactor: Double
    let duration: Double
    let numClipped: UInt32

    static func analyze(signal: AudioSignal) -> AudioStats {
        var result = SndysStats()
        sndys_analyze_stats(signal.samples, signal.numSamples, signal.sampleRate, &result)
        return AudioStats(
            rmsDB: result.rmsDB,
            peakDB: result.peakDB,
            crestFactor: result.crestFactor,
            duration: result.duration,
            numClipped: result.numClipped
        )
    }
}

/// Key detection result
struct KeyResult {
    let name: String
    let confidence: Double

    static func detect(signal: AudioSignal) -> KeyResult {
        var buf = [CChar](repeating: 0, count: 32)
        var conf: Double = 0
        sndys_detect_key(signal.samples, signal.numSamples, signal.sampleRate,
                         &buf, 32, &conf)
        return KeyResult(name: String(cString: buf), confidence: conf)
    }
}

/// Beat/tempo result
struct BeatResult {
    let bpm: Double
    let confidence: Double
    let beatStrength: Double

    static func detect(signal: AudioSignal) -> BeatResult {
        var bpm: Double = 0
        var conf: Double = 0
        let _ = sndys_detect_beats(signal.samples, signal.numSamples,
                                   signal.sampleRate, &bpm, &conf)
        let strength = sndys_beat_strength(signal.samples, signal.numSamples,
                                           signal.sampleRate)
        return BeatResult(bpm: bpm, confidence: conf, beatStrength: strength)
    }
}

/// Onset times
struct OnsetResult {
    let times: [Double]

    static func detect(signal: AudioSignal, sensitivity: Double = 1.5) -> OnsetResult {
        var onsets = [Double](repeating: 0, count: 4096)
        let count = sndys_detect_onsets(signal.samples, signal.numSamples,
                                        signal.sampleRate, sensitivity,
                                        &onsets, 4096)
        return OnsetResult(times: Array(onsets.prefix(Int(count))))
    }
}

/// Spectrogram data
class SpectrogramData {
    let data: UnsafeMutablePointer<Double>
    let numFrames: UInt32
    let numBins: UInt32

    init(data: UnsafeMutablePointer<Double>, numFrames: UInt32, numBins: UInt32) {
        self.data = data
        self.numFrames = numFrames
        self.numBins = numBins
    }

    deinit {
        sndys_free_spectro(data, numFrames * numBins)
    }

    func value(frame: Int, bin: Int) -> Double {
        data[frame * Int(numBins) + bin]
    }

    static func compute(signal: AudioSignal) -> SpectrogramData? {
        var nf: UInt32 = 0
        var nb: UInt32 = 0
        guard let ptr = sndys_compute_spectrogram(signal.samples, signal.numSamples,
                                                   signal.sampleRate, &nf, &nb),
              nf > 0 else { return nil }
        return SpectrogramData(data: ptr, numFrames: nf, numBins: nb)
    }
}

/// Chord sequence
struct ChordEvent {
    let name: String
    let confidence: Double
}

class ChordSequence {
    private let data: UnsafeMutablePointer<SndysChord>
    private let count: UInt32

    init(data: UnsafeMutablePointer<SndysChord>, count: UInt32) {
        self.data = data
        self.count = count
    }

    deinit {
        sndys_free_chords(data, count)
    }

    var chords: [ChordEvent] {
        (0..<Int(count)).map { i in
            let c = data[i]
            // Safe extraction: copy name tuple to a buffer
            var buf = [CChar](repeating: 0, count: 17)
            withUnsafeBytes(of: c.name) { raw in
                let count = min(raw.count, 16)
                for j in 0..<count {
                    buf[j] = CChar(bitPattern: raw[j])
                }
            }
            buf[16] = 0
            return ChordEvent(name: String(cString: buf), confidence: c.confidence)
        }
    }

    static func detect(signal: AudioSignal) -> ChordSequence? {
        var count: UInt32 = 0
        guard let ptr = sndys_detect_chords(signal.samples, signal.numSamples,
                                             signal.sampleRate, &count),
              count > 0 else { return nil }
        return ChordSequence(data: ptr, count: count)
    }
}

/// Pitch contour
class PitchContour {
    let pitches: UnsafeMutablePointer<Double>
    let times: UnsafeMutablePointer<Double>?
    let numFrames: UInt32

    init(pitches: UnsafeMutablePointer<Double>,
         times: UnsafeMutablePointer<Double>?,
         numFrames: UInt32) {
        self.pitches = pitches
        self.times = times
        self.numFrames = numFrames
    }

    deinit {
        sndys_free_pitch(pitches, times, numFrames)
    }

    func f0(at frame: Int) -> Double {
        guard frame < numFrames else { return 0 }
        return pitches[frame]
    }

    static func track(signal: AudioSignal) -> PitchContour? {
        var pitchPtr: UnsafeMutablePointer<Double>?
        var timesPtr: UnsafeMutablePointer<Double>?
        var nf: UInt32 = 0
        sndys_track_pitch(signal.samples, signal.numSamples,
                           signal.sampleRate, &pitchPtr, &timesPtr, &nf)
        guard let p = pitchPtr, nf > 0 else { return nil }
        return PitchContour(pitches: p, times: timesPtr, numFrames: nf)
    }
}

/// Note event
struct NoteEvent {
    let startSec: Double
    let endSec: Double
    let pitchHz: Double
    let midiNote: Int32
    let name: String
}

class NoteSequence {
    private let data: UnsafeMutablePointer<SndysNote>
    private let count: UInt32

    init(data: UnsafeMutablePointer<SndysNote>, count: UInt32) {
        self.data = data
        self.count = count
    }

    deinit {
        sndys_free_notes(data, count)
    }

    var notes: [NoteEvent] {
        (0..<Int(count)).map { i in
            let n = data[i]
            var buf = [CChar](repeating: 0, count: 9)
            withUnsafeBytes(of: n.noteName) { raw in
                let count = min(raw.count, 8)
                for j in 0..<count {
                    buf[j] = CChar(bitPattern: raw[j])
                }
            }
            buf[8] = 0
            return NoteEvent(startSec: n.startSec, endSec: n.endSec,
                           pitchHz: n.pitchHz, midiNote: n.midiNote,
                           name: String(cString: buf))
        }
    }

    static func transcribe(signal: AudioSignal) -> NoteSequence? {
        var count: UInt32 = 0
        guard let ptr = sndys_transcribe(signal.samples, signal.numSamples,
                                          signal.sampleRate, &count),
              count > 0 else { return nil }
        return NoteSequence(data: ptr, count: count)
    }
}

/// Voice features
struct VoiceResult {
    let f1: Double, f2: Double, f3: Double
    let jitter: Double
    let shimmer: Double
    let hnr: Double

    static func analyze(signal: AudioSignal, pitch: PitchContour?) -> VoiceResult {
        var result = SndysVoice()
        let pitchPtr: UnsafeMutablePointer<Double>? = pitch?.pitches
        let pitchFrames: UInt32 = pitch?.numFrames ?? 0
        sndys_voice_features(signal.samples, signal.numSamples, signal.sampleRate,
                             pitchPtr, pitchFrames, &result)
        return VoiceResult(f1: result.f1, f2: result.f2, f3: result.f3,
                          jitter: result.jitter, shimmer: result.shimmer,
                          hnr: result.hnr)
    }
}

/// Feature name lookup
func featureName(_ idx: Int) -> String {
    guard let cstr = sndys_feature_name(UInt32(idx)) else { return "Unknown" }
    return String(cString: cstr)
}
