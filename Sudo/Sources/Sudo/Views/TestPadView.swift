import SwiftUI
import AppKit

/// A virtual macro pad for testing without the physical device.
/// Shows 4 keycap-styled buttons stacked vertically, mimicking the real pad layout.
struct TestPadView: View {
    @ObservedObject var engine: SudoEngine
    @ObservedObject var configStore: ButtonConfigStore = .shared

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("[sudo] test pad")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: 0x00FF41))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Keycaps
            VStack(spacing: 2) {
                ForEach(PadAction.allCases, id: \.rawValue) { action in
                    KeycapButton(action: action, configStore: configStore) {
                        engine.simulateAction(action)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 148)
        .background(Color(hex: 0x0A0A0A))
    }
}

/// A single keycap-styled button with 3D depth effect and press animation.
private struct KeycapButton: View {
    let action: PadAction
    let configStore: ButtonConfigStore
    let onPress: () -> Void

    @State private var isPressed = false

    var body: some View {
        let mode = configStore.buttonMode(for: action)
        let label: String = {
            if case .simple(let simpleAction) = mode {
                return simpleAction.displayName
            }
            return action.displayName
        }()
        let hotkeyString = configStore.hotkeyConfig(for: action).displayString

        Button(action: {
            withAnimation(.easeInOut(duration: 0.08)) { isPressed = true }
            onPress()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeInOut(duration: 0.08)) { isPressed = false }
            }
        }) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(hotkeyString)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(hex: 0x555555))
            }
            .frame(width: 120, height: 50)
            .background(
                ZStack {
                    // Base shadow / depth
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(hex: 0x1A1A1A))

                    // Top highlight edge
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(hex: 0x3A3A3A),
                                    Color(hex: 0x252525),
                                    Color(hex: 0x1A1A1A),
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Inset keycap surface
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(hex: 0x333333),
                                    Color(hex: 0x222222),
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(.top, 1)
                        .padding(.bottom, 3)
                        .padding(.horizontal, 1)
                }
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .brightness(isPressed ? -0.1 : 0)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Window Controller

/// Manages the floating test pad window lifecycle.
final class TestPadWindowController {
    static let shared = TestPadWindowController()
    private var window: NSWindow?

    func showWindow(engine: SudoEngine) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = TestPadView(engine: engine)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 148, height: 240)

        let w = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        w.contentView = hostingView
        w.title = "Sudo Test Pad"
        w.isFloatingPanel = true
        w.level = .floating
        w.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)
        w.isMovableByWindowBackground = true
        w.center()
        w.makeKeyAndOrderFront(nil)

        self.window = w
    }
}
