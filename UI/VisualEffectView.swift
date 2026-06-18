import SwiftUI
import AppKit

// MARK: - VisualEffectView

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    init(
        _ material: NSVisualEffectView.Material = .sidebar,   // .sidebar = lighter, more neutral than .underWindowBackground
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material     = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material     = material
        v.blendingMode = blendingMode
        v.state        = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material     = material
        v.blendingMode = blendingMode
    }
}

// MARK: - Window Transparency Probe

private struct WindowTransparencyConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        DispatchQueue.main.async {
            guard let w = probe.window else { return }
            w.isOpaque        = false
            w.backgroundColor = .clear
            w.hasShadow       = true
        }
        return probe
    }
    func updateNSView(_ nsView: NSView, context: Context) { }
}

// MARK: - View Extensions

extension View {

    /// Primary glass window treatment.
    /// .sidebar is significantly lighter / more neutral than .underWindowBackground —
    /// it doesn't over-absorb warm wallpaper tones.
    func glassWindow(
        _ material: NSVisualEffectView.Material = .sidebar
    ) -> some View {
        background(
            ZStack {
                VisualEffectView(material, blendingMode: .behindWindow)
                WindowTransparencyConfigurator()
            }
            .ignoresSafeArea()
        )
    }

    /// Liquid Glass card on macOS 26 (Tahoe); falls back to ultraThinMaterial on Sonoma/Sequoia.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }

    /// Subtle tinted card for sections that need less contrast than glassCard.
    func tintedCard(cornerRadius: CGFloat = 10, opacity: CGFloat = 0.06) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(opacity))
        )
    }
}
