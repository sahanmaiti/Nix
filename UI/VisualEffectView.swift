import SwiftUI
import AppKit

// NSVisualEffectView wrapper for SwiftUI
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    init(
        _ material: NSVisualEffectView.Material = .underWindowBackground,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// Reads the hosting window one run-loop tick after insertion and
// makes it transparent so the vibrancy blur renders correctly.
private struct WindowTransparencyConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        DispatchQueue.main.async {
            guard let window = probe.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        return probe
    }
    func updateNSView(_ nsView: NSView, context: Context) { }
}

extension View {
    /// Applies frosted-glass NSVisualEffectView and makes the
    /// hosting NSWindow transparent so the blur renders correctly.
    func glassWindow(
        _ material: NSVisualEffectView.Material = .underWindowBackground
    ) -> some View {
        background(
            ZStack {
                VisualEffectView(material, blendingMode: .behindWindow)
                WindowTransparencyConfigurator()
            }
            .ignoresSafeArea()
        )
    }
}
