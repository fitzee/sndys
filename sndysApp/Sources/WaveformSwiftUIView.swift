// WaveformSwiftUIView.swift — Waveform with playback cursor and click-to-seek
import SwiftUI

struct WaveformSwiftUIView: View {
    let signal: AudioSignal
    @EnvironmentObject var store: AnalysisStore

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                WaveformCanvas(signal: signal)

                // Playback cursor line
                if store.playbackPosition > 0 || store.isPlaying {
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 1.5)
                        .offset(x: geo.size.width * CGFloat(store.playbackPosition))
                        .animation(.linear(duration: 0.03), value: store.playbackPosition)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let pos = Double(value.location.x / geo.size.width)
                        store.seekTo(position: pos)
                    }
            )
        }
        .background(Color(nsColor: NSColor(white: 0.08, alpha: 1)))
        .onHover { inside in
            if inside { NSCursor.iBeam.push() } else { NSCursor.pop() }
        }
    }
}

struct WaveformCanvas: NSViewRepresentable {
    let signal: AudioSignal

    func makeNSView(context: Context) -> WaveformNSView {
        WaveformNSView(signal: signal)
    }

    func updateNSView(_ nsView: WaveformNSView, context: Context) {
        nsView.signal = signal
        nsView.needsDisplay = true
    }
}

class WaveformNSView: NSView {
    var signal: AudioSignal?

    init(signal: AudioSignal) {
        self.signal = signal
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width, h = bounds.height

        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        ctx.fill(bounds)

        guard let sig = signal, sig.numSamples > 0 else { return }

        let midY = h / 2
        let n = Int(sig.numSamples), cols = Int(w)

        // Center line
        ctx.setStrokeColor(CGColor(gray: 0.2, alpha: 1))
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: 0, y: midY))
        ctx.addLine(to: CGPoint(x: w, y: midY))
        ctx.strokePath()

        // Waveform bars
        ctx.setFillColor(NSColor.systemGreen.withAlphaComponent(0.85).cgColor)
        for col in 0..<cols {
            let s = col * n / cols
            var e = (col + 1) * n / cols
            if e > n { e = n }; if e <= s { continue }
            var lo: Double = 0, hi: Double = 0
            for i in s..<e {
                let v = sig.samples[i]
                if v < lo { lo = v }; if v > hi { hi = v }
            }
            let topY = midY - CGFloat(hi) * midY
            let botY = midY - CGFloat(lo) * midY
            ctx.fill(CGRect(x: CGFloat(col), y: topY, width: 1, height: max(1, botY - topY)))
        }
    }
}
