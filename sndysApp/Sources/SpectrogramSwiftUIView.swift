// SpectrogramSwiftUIView.swift — Spectrogram/chromagram with crosshair cursor
import SwiftUI

struct SpectrogramSwiftUIView: View {
    let data: SpectrogramData?

    var body: some View {
        SpectrogramCanvas(data: data)
            .onHover { inside in
                if inside && data != nil { NSCursor.crosshair.push() } else { NSCursor.pop() }
            }
    }
}

struct SpectrogramCanvas: NSViewRepresentable {
    let data: SpectrogramData?

    func makeNSView(context: Context) -> SpectrogramNSView { SpectrogramNSView() }

    func updateNSView(_ nsView: SpectrogramNSView, context: Context) {
        nsView.data = data
        nsView.needsDisplay = true
    }
}

class SpectrogramNSView: NSView {
    var data: SpectrogramData?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = Int(bounds.width), h = Int(bounds.height)

        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        ctx.fill(bounds)

        guard let data = data, data.numFrames > 0, data.numBins > 0,
              w > 0, h > 0 else { return }

        let nf = Int(data.numFrames), nb = Int(data.numBins)
        var maxVal: Double = 0
        for i in 0..<(nf * nb) { if data.data[i] > maxVal { maxVal = data.data[i] } }
        if maxVal < 1e-20 { maxVal = 1e-20 }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for col in 0..<w {
            let fi = col * nf / w
            for row in 0..<h {
                let bi = (h - 1 - row) * nb / h
                var val = data.data[fi * nb + bi] / maxVal
                if val < 1e-10 { val = 0 } else { val = pow(val, 0.3) }
                let (r, g, b) = heatColor(val)
                let idx = (row * w + col) * 4
                pixels[idx] = r; pixels[idx+1] = g; pixels[idx+2] = b; pixels[idx+3] = 255
            }
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        if let prov = CGDataProvider(data: Data(pixels) as CFData),
           let img = CGImage(width: w, height: h, bitsPerComponent: 8,
                            bitsPerPixel: 32, bytesPerRow: w * 4, space: cs,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: prov, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent) {
            ctx.draw(img, in: bounds)
        }
    }

    func heatColor(_ v: Double) -> (UInt8, UInt8, UInt8) {
        let t = max(0, min(1, v)) * 4
        let r: Double, g: Double, b: Double
        if t < 1 { r = 0; g = t; b = 1 }
        else if t < 2 { r = 0; g = 1; b = 2 - t }
        else if t < 3 { r = t - 2; g = 1; b = 0 }
        else { r = 1; g = 4 - t; b = 0 }
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
    }
}
