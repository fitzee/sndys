// AnalysisStore.swift — Observable state for all analysis data
import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

class AnalysisStore: ObservableObject {
    // File
    @Published var signal: AudioSignal?
    @Published var fileName: String = ""
    @Published var status: String = "Open a file to begin"
    @Published var isAnalyzing: Bool = false
    @Published var wantsFileOpen: Bool = false

    // Results
    @Published var statsResult: AudioStats?
    @Published var keyResult: KeyResult?
    @Published var beatResult: BeatResult?
    @Published var spectroData: SpectrogramData?
    @Published var chromaResult: SpectrogramData?
    @Published var pitchData: PitchContour?
    @Published var chordData: ChordSequence?
    @Published var noteData: NoteSequence?
    @Published var onsetResult: OnsetResult?
    @Published var voiceResult: VoiceResult?
    @Published var featuresText: String = ""

    // Playback
    @Published var isPlaying: Bool = false
    @Published var playbackPosition: Double = 0  // 0..1
    var audioPlayer: AVAudioPlayer?
    var playbackTimer: Timer?

    // Analysis serialization
    private let lock = NSLock()

    private func runAnalysis(_ label: String, _ work: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async { self.isAnalyzing = true; self.status = label }
        let keepAlive = signal
        let thread = Thread {
            self.lock.lock()
            withExtendedLifetime(keepAlive) { work() }
            self.lock.unlock()
        }
        thread.stackSize = 8 * 1024 * 1024
        thread.start()
    }

    private func done(_ msg: String) {
        DispatchQueue.main.async { self.isAnalyzing = false; self.status = msg }
    }

    // MARK: - File

    func openFile() {
        wantsFileOpen = true
    }

    func loadFile(path: String) {
        stopPlayback()
        runAnalysis("Loading...") { [weak self] in
            let sig = AudioSignal.load(path: path)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.clearResults()
                self.signal = sig
                self.fileName = (path as NSString).lastPathComponent
                if let sig = sig {
                    self.status = "\(sig.sampleRate) Hz · \(sig.numSamples) samples · \(String(format: "%.1f", sig.duration))s"
                } else {
                    self.status = "Error loading file"
                }
                self.isAnalyzing = false
            }
        }
    }

    func clearResults() {
        statsResult = nil; keyResult = nil; beatResult = nil
        spectroData = nil; chromaResult = nil; pitchData = nil
        chordData = nil; noteData = nil; onsetResult = nil
        voiceResult = nil; featuresText = ""
        playbackPosition = 0
    }

    // MARK: - Playback

    func togglePlayback() {
        if isPlaying { stopPlayback() } else { startPlayback(from: playbackPosition) }
    }

    func startPlayback(from position: Double) {
        guard let sig = signal else { return }
        stopPlayback()
        do {
            audioPlayer = try AVAudioPlayer(data: makeWAV(sig))
            audioPlayer?.currentTime = position * sig.duration
            audioPlayer?.play()
            isPlaying = true
            status = "Playing..."
            // Timer to update position
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
                guard let self = self, let player = self.audioPlayer else { return }
                if player.isPlaying {
                    self.playbackPosition = player.currentTime / sig.duration
                } else {
                    self.stopPlayback()
                }
            }
        } catch {
            status = "Playback error"
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
        if signal != nil { status = "\(fileName)" }
    }

    func seekTo(position: Double) {
        playbackPosition = max(0, min(1, position))
        if isPlaying {
            startPlayback(from: playbackPosition)
        }
    }

    // MARK: - Analysis

    func analyzeOverview() {
        guard let sig = signal else { return }
        runAnalysis("Computing overview...") { [weak self] in
            let stats = AudioStats.analyze(signal: sig)
            let key = KeyResult.detect(signal: sig)
            let beat = BeatResult.detect(signal: sig)
            DispatchQueue.main.async {
                self?.statsResult = stats; self?.keyResult = key; self?.beatResult = beat
                self?.done("Overview complete")
            }
        }
    }

    func analyzeSpectrum() {
        guard let sig = signal, spectroData == nil else { return }
        runAnalysis("Computing spectrogram...") { [weak self] in
            let spectro = SpectrogramData.compute(signal: sig)
            var nf: UInt32 = 0
            let cp = sndys_compute_chromagram(sig.samples, sig.numSamples,
                                               sig.sampleRate, &nf)
            var chroma: SpectrogramData? = nil
            if let p = cp, nf > 0 {
                chroma = SpectrogramData(data: p, numFrames: nf, numBins: 12)
            }
            DispatchQueue.main.async {
                self?.spectroData = spectro; self?.chromaResult = chroma
                self?.done("Spectral analysis complete")
            }
        }
    }

    func analyzeTempo() {
        guard let sig = signal, beatResult == nil else { return }
        runAnalysis("Analyzing tempo...") { [weak self] in
            let beat = BeatResult.detect(signal: sig)
            let onsets = OnsetResult.detect(signal: sig)
            DispatchQueue.main.async {
                self?.beatResult = beat; self?.onsetResult = onsets
                self?.done("Tempo analysis complete")
            }
        }
    }

    func analyzeHarmonic() {
        guard let sig = signal, pitchData == nil else { return }
        runAnalysis("Analyzing harmonic...") { [weak self] in
            let pitch = PitchContour.track(signal: sig)
            let chords = ChordSequence.detect(signal: sig)
            let notes = NoteSequence.transcribe(signal: sig)
            let voice = withExtendedLifetime((sig, pitch)) {
                VoiceResult.analyze(signal: sig, pitch: pitch)
            }
            DispatchQueue.main.async {
                self?.pitchData = pitch; self?.chordData = chords
                self?.noteData = notes; self?.voiceResult = voice
                self?.done("Harmonic analysis complete")
            }
        }
    }

    func analyzeFeatures() {
        guard let sig = signal, featuresText.isEmpty else { return }
        runAnalysis("Extracting features...") { [weak self] in
            var nf: UInt32 = 0
            let feats = sndys_extract_features(sig.samples, sig.numSamples,
                                                sig.sampleRate, &nf)
            DispatchQueue.main.async {
                guard let feats = feats, nf > 0 else {
                    self?.featuresText = "Failed"; self?.done("Extraction failed"); return
                }
                var lines: [String] = []
                for i in 0..<34 {
                    lines.append("\(featureName(i))|\(String(format: "%.6f", feats[i]))")
                }
                sndys_free_features(feats, nf)
                self?.featuresText = lines.joined(separator: "\n")
                self?.done("Features extracted (\(nf) frames)")
            }
        }
    }

    func analyzeAll() {
        guard let sig = signal else { return }
        runAnalysis("Full analysis...") { [weak self] in
            let stats = AudioStats.analyze(signal: sig)
            let key = KeyResult.detect(signal: sig)
            let beat = BeatResult.detect(signal: sig)
            let onsets = OnsetResult.detect(signal: sig)
            let spectro = SpectrogramData.compute(signal: sig)
            var chromaNf: UInt32 = 0
            let cp = sndys_compute_chromagram(sig.samples, sig.numSamples,
                                               sig.sampleRate, &chromaNf)
            var chroma: SpectrogramData? = nil
            if let p = cp, chromaNf > 0 {
                chroma = SpectrogramData(data: p, numFrames: chromaNf, numBins: 12)
            }
            let pitch = PitchContour.track(signal: sig)
            let chords = ChordSequence.detect(signal: sig)
            let notes = NoteSequence.transcribe(signal: sig)
            let voice = withExtendedLifetime((sig, pitch)) {
                VoiceResult.analyze(signal: sig, pitch: pitch)
            }
            DispatchQueue.main.async {
                self?.statsResult = stats; self?.keyResult = key
                self?.beatResult = beat; self?.onsetResult = onsets
                self?.spectroData = spectro; self?.chromaResult = chroma
                self?.pitchData = pitch; self?.chordData = chords
                self?.noteData = notes; self?.voiceResult = voice
                self?.done("Analysis complete")
            }
        }
    }

    // MARK: - WAV

    private func makeWAV(_ sig: AudioSignal) -> Data {
        let n = Int(sig.numSamples), sr = Int(sig.sampleRate)
        let dataSize = n * 2, fileSize = 44 + dataSize
        var d = Data(capacity: fileSize)
        func u32(_ v: UInt32) { d.append(contentsOf: withUnsafeBytes(of: v.littleEndian){Array($0)}) }
        func u16(_ v: UInt16) { d.append(contentsOf: withUnsafeBytes(of: v.littleEndian){Array($0)}) }
        d.append(contentsOf: [0x52,0x49,0x46,0x46]); u32(UInt32(fileSize-8))
        d.append(contentsOf: [0x57,0x41,0x56,0x45,0x66,0x6D,0x74,0x20])
        u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr*2)); u16(2); u16(16)
        d.append(contentsOf: [0x64,0x61,0x74,0x61]); u32(UInt32(dataSize))
        for i in 0..<n {
            var v = sig.samples[i]; v = max(-1, min(1, v))
            d.append(contentsOf: withUnsafeBytes(of: Int16(v * 32767).littleEndian){Array($0)})
        }
        return d
    }
}
