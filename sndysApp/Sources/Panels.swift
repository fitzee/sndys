// Panels.swift — Analysis detail panels for each sidebar section
import SwiftUI

// MARK: - Overview

struct OverviewPanel: View {
    @EnvironmentObject var store: AnalysisStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let sig = store.signal {
                    SectionHeader("File Info", icon: "doc.text")
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        InfoRow("Samples", "\(sig.numSamples)")
                        InfoRow("Sample Rate", "\(sig.sampleRate) Hz")
                        InfoRow("Duration", "\(String(format: "%.2f", sig.duration))s")
                    }
                }
                if let st = store.statsResult {
                    SectionHeader("Audio Stats", icon: "chart.bar")
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        InfoRow("RMS Level", "\(String(format: "%.1f", st.rmsDB)) dBFS")
                        InfoRow("Peak Level", "\(String(format: "%.1f", st.peakDB)) dBFS")
                        InfoRow("Crest Factor", "\(String(format: "%.1f", st.crestFactor)) dB")
                        if st.numClipped > 0 {
                            InfoRow("Clipped", "\(st.numClipped) samples")
                        }
                    }
                }
                if let k = store.keyResult {
                    SectionHeader("Key Detection", icon: "music.note")
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        InfoRow("Key", k.name)
                        InfoRow("Confidence", String(format: "%.2f", k.confidence))
                    }
                }
                if let b = store.beatResult {
                    SectionHeader("Tempo", icon: "metronome")
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        InfoRow("BPM", String(format: "%.1f", b.bpm))
                        InfoRow("Confidence", "\(String(format: "%.0f", b.confidence * 100))%")
                        InfoRow("Beat Strength", String(format: "%.3f", b.beatStrength))
                    }
                }
                if store.statsResult == nil && !store.isAnalyzing {
                    Text("Click a section in the sidebar to analyze.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                Spacer()
            }
            .padding()
        }
        .onAppear {
            if store.signal != nil && store.statsResult == nil && !store.isAnalyzing {
                store.analyzeOverview()
            }
        }
    }
}

// MARK: - Spectrum

struct SpectrumPanel: View {
    @EnvironmentObject var store: AnalysisStore

    var body: some View {
        if store.spectroData == nil && !store.isAnalyzing {
            VStack {
                ProgressView()
                Text("Computing...").foregroundStyle(.secondary)
            }
            .onAppear { store.analyzeSpectrum() }
        } else {
            VStack(spacing: 4) {
                SectionHeader("Spectrogram", icon: "waveform.path")
                    .padding(.horizontal)
                SpectrogramSwiftUIView(data: store.spectroData)
                    .frame(maxHeight: .infinity)

                SectionHeader("Chromagram", icon: "pianokeys")
                    .padding(.horizontal)
                SpectrogramSwiftUIView(data: store.chromaResult)
                    .frame(maxHeight: .infinity)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Tempo

struct TempoPanel: View {
    @EnvironmentObject var store: AnalysisStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let b = store.beatResult {
                    SectionHeader("Tempo / Beat", icon: "metronome.fill")
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        InfoRow("BPM", String(format: "%.1f", b.bpm))
                        InfoRow("Confidence", "\(String(format: "%.0f", b.confidence * 100))%")
                        InfoRow("Beat Strength", String(format: "%.3f", b.beatStrength))
                    }
                }
                if let o = store.onsetResult, !o.times.isEmpty {
                    SectionHeader("Onsets (\(o.times.count))", icon: "bolt.fill")
                    LazyVGrid(columns: [
                        GridItem(.fixed(50), alignment: .trailing),
                        GridItem(.fixed(90), alignment: .trailing)
                    ], alignment: .leading, spacing: 2) {
                        Text("#").font(.caption).foregroundStyle(.tertiary)
                        Text("Time").font(.caption).foregroundStyle(.tertiary)
                        ForEach(Array(o.times.prefix(200).enumerated()), id: \.offset) { i, t in
                            Text("\(i)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text("\(String(format: "%.3f", t))s").font(.caption.monospacedDigit())
                        }
                    }
                    if o.times.count > 200 {
                        Text("... \(o.times.count - 200) more")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding()
        }
        .onAppear {
            if store.signal != nil && store.beatResult == nil && !store.isAnalyzing {
                store.analyzeTempo()
            }
        }
    }
}

// MARK: - Harmonic

struct HarmonicPanel: View {
    @EnvironmentObject var store: AnalysisStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let p = store.pitchData {
                    let voiced = (0..<Int(p.numFrames)).filter { p.f0(at: $0) > 0 }.count
                    SectionHeader("Pitch Contour", icon: "waveform")
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        InfoRow("Frames", "\(p.numFrames)")
                        InfoRow("Voiced", "\(voiced) (\(String(format: "%.0f", Double(voiced)/Double(p.numFrames)*100))%)")
                    }
                }
                if let v = store.voiceResult {
                    SectionHeader("Voice Features", icon: "person.wave.2")
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        InfoRow("Formant F1", "\(String(format: "%.0f", v.f1)) Hz")
                        InfoRow("Formant F2", "\(String(format: "%.0f", v.f2)) Hz")
                        InfoRow("Formant F3", "\(String(format: "%.0f", v.f3)) Hz")
                        InfoRow("Jitter", "\(String(format: "%.2f", v.jitter * 100))%")
                        InfoRow("Shimmer", "\(String(format: "%.2f", v.shimmer * 100))%")
                        InfoRow("HNR", "\(String(format: "%.1f", v.hnr)) dB")
                    }
                }
                if let c = store.chordData {
                    SectionHeader("Chords (\(c.chords.count))", icon: "music.quarternote.3")
                    LazyVGrid(columns: [
                        GridItem(.fixed(70), alignment: .leading),
                        GridItem(.fixed(60), alignment: .trailing)
                    ], alignment: .leading, spacing: 2) {
                        Text("Chord").font(.caption).foregroundStyle(.tertiary)
                        Text("Conf").font(.caption).foregroundStyle(.tertiary)
                        ForEach(Array(c.chords.prefix(100).enumerated()), id: \.offset) { _, ch in
                            Text(ch.name).font(.body.monospaced().bold())
                            Text(String(format: "%.2f", ch.confidence))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    if c.chords.count > 100 {
                        Text("... \(c.chords.count - 100) more")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                if let n = store.noteData {
                    SectionHeader("Notes (\(n.notes.count))", icon: "music.note.list")
                    LazyVGrid(columns: [
                        GridItem(.fixed(70), alignment: .trailing),
                        GridItem(.fixed(50), alignment: .leading),
                        GridItem(.fixed(80), alignment: .trailing)
                    ], alignment: .leading, spacing: 2) {
                        Text("Time").font(.caption).foregroundStyle(.tertiary)
                        Text("Note").font(.caption).foregroundStyle(.tertiary)
                        Text("Pitch").font(.caption).foregroundStyle(.tertiary)
                        ForEach(Array(n.notes.prefix(100).enumerated()), id: \.offset) { _, note in
                            Text("\(String(format: "%.2f", note.startSec))s")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(note.name).font(.body.monospaced().bold())
                            Text("\(String(format: "%.0f", note.pitchHz)) Hz")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    if n.notes.count > 100 {
                        Text("... \(n.notes.count - 100) more")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding()
        }
        .onAppear {
            if store.signal != nil && store.pitchData == nil && !store.isAnalyzing {
                store.analyzeHarmonic()
            }
        }
    }
}

// MARK: - Features

struct FeaturesPanel: View {
    @EnvironmentObject var store: AnalysisStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Short-Term Features", icon: "list.bullet.rectangle.fill")
                if store.featuresText.isEmpty {
                    if store.isAnalyzing {
                        ProgressView("Extracting...")
                    } else {
                        Text("Select this tab to extract features.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                        GridRow {
                            Text("Feature").font(.caption.bold()).foregroundStyle(.tertiary)
                            Text("Value").font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                        Divider()
                        ForEach(store.featuresText.split(separator: "\n"), id: \.self) { line in
                            let parts = line.split(separator: "|")
                            if parts.count == 2 {
                                GridRow {
                                    Text(parts[0]).font(.body)
                                    Text(parts[1]).font(.body.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding()
        }
        .onAppear {
            if store.signal != nil && store.featuresText.isEmpty && !store.isAnalyzing {
                store.analyzeFeatures()
            }
        }
    }
}

// MARK: - Shared components

struct SectionHeader: View {
    let title: String
    let icon: String

    init(_ title: String, icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.top, 4)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        GridRow {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}
