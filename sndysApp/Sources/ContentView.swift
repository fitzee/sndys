// ContentView.swift — Main NavigationSplitView layout
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case spectrum = "Spectrum"
    case tempo = "Tempo"
    case harmonic = "Harmonic"
    case features = "Features"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "info.circle.fill"
        case .spectrum: return "waveform.path"
        case .tempo:    return "metronome.fill"
        case .harmonic: return "music.note.list"
        case .features: return "list.bullet.rectangle.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: AnalysisStore
    @State private var selectedItem: SidebarItem? = .overview
    @State private var showFileImporter = false

    // Sync store's wantsFileOpen → local showFileImporter
    private func checkFileOpen() {
        if store.wantsFileOpen {
            store.wantsFileOpen = false
            showFileImporter = true
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedItem = item
                        triggerAnalysis(item)
                    }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            VStack(spacing: 0) {
                // Toolbar area
                HStack(spacing: 12) {
                    Button { showFileImporter = true } label: {
                        Label("Open", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("o")

                    Button(action: { store.togglePlayback() }) {
                        Label(store.isPlaying ? "Pause" : "Play",
                              systemImage: store.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.signal == nil)

                    Button(action: { store.analyzeAll() }) {
                        Label("Analyze All", systemImage: "waveform.badge.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.signal == nil || store.isAnalyzing)

                    Spacer()

                    if store.isAnalyzing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                        Text(store.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)

                Divider()

                // Waveform
                if store.signal != nil {
                    WaveformSwiftUIView(signal: store.signal!)
                        .frame(height: 150)
                } else {
                    ZStack {
                        Color(nsColor: .controlBackgroundColor)
                        VStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.system(size: 40))
                                .foregroundStyle(.tertiary)
                            Text("Open a WAV file to begin")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 150)
                }

                Divider()

                // Analysis content
                if store.signal == nil {
                    Spacer()
                } else {
                    detailView
                }

                Divider()

                // Status bar
                HStack {
                    Text(store.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if store.signal != nil {
                        Text(store.fileName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.bar)
            }
        }
        .onChange(of: selectedItem) { item in
            triggerAnalysis(item)
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.wav, .audio]) { result in
            if case .success(let url) = result {
                store.loadFile(path: url.path)
            }
        }
        .onChange(of: store.wantsFileOpen) { wants in
            if wants {
                store.wantsFileOpen = false
                showFileImporter = true
            }
        }
    }

    @ViewBuilder
    var detailView: some View {
        switch selectedItem {
        case .overview:  OverviewPanel()
        case .spectrum:  SpectrumPanel()
        case .tempo:     TempoPanel()
        case .harmonic:  HarmonicPanel()
        case .features:  FeaturesPanel()
        case nil:        Text("Select a section").foregroundStyle(.secondary)
        }
    }

    func triggerAnalysis(_ item: SidebarItem?) {
        guard store.signal != nil, !store.isAnalyzing else { return }
        switch item {
        case .overview:  if store.statsResult == nil { store.analyzeOverview() }
        case .spectrum:  if store.spectroData == nil { store.analyzeSpectrum() }
        case .tempo:     if store.beatResult == nil { store.analyzeTempo() }
        case .harmonic:  if store.pitchData == nil { store.analyzeHarmonic() }
        case .features:  if store.featuresText.isEmpty { store.analyzeFeatures() }
        case nil: break
        }
    }
}
