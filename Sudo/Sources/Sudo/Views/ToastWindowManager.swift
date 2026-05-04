import AppKit
import SwiftUI

/// Floating toast that appears below the menu bar to surface things the
/// user wouldn't otherwise see — most importantly, when an AI-search
/// press fails to find a matching button. Without this they'd just see
/// "nothing happened" and have no way to tell whether the keystroke
/// reached the app.
///
/// Implemented as a borderless `NSPanel` at floating level so it doesn't
/// take focus or appear in the dock / window list. Auto-dismisses on a
/// timer.
final class ToastWindowManager {
    static let shared = ToastWindowManager()
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    /// Show a failure toast.
    func showFailure(action: String, app: String) {
        DispatchQueue.main.async { [weak self] in
            self?.show(
                ToastView(
                    title: "couldn't \(action.lowercased())",
                    detail: app.isEmpty ? "no matching button found" : "in \(app.lowercased())",
                    isError: true
                )
            )
        }
    }

    /// Show a generic info toast (currently unused; reserved for things like
    /// "preset switched to media controls" if we want to surface auto-switch).
    func showInfo(_ title: String, detail: String? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.show(
                ToastView(title: title, detail: detail ?? "", isError: false)
            )
        }
    }

    // MARK: - Private

    private func show<Content: View>(_ content: Content) {
        if panel == nil { panel = makePanel() }
        guard let panel = panel else { return }

        panel.contentView = NSHostingView(rootView: content
            .frame(width: 300, height: 64))
        position(panel: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }

        // Cancel any in-flight dismissal and schedule a fresh one
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func dismiss() {
        guard let panel = panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.isMovableByWindowBackground = false
        p.hasShadow = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        return p
    }

    /// Pin the toast to the top-right of the menu-bar screen, just below
    /// the menu bar with a 12pt right margin.
    private func position(panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - 12,
            y: visible.maxY - size.height - 8
        )
        panel.setFrameOrigin(origin)
    }
}

// MARK: - Toast view

private struct ToastView: View {
    let title: String
    let detail: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(isError ? SudoTheme.error : SudoTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SudoTheme.bodyEmphasized)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(SudoTheme.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SudoTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}
