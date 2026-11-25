import AppKit
import KoolsCore
import SwiftUI
import UniformTypeIdentifiers

/// A floating shelf for parking files, links and text. Shake the pointer
/// while dragging something and the shelf appears next to it; it can also
/// be opened from the menu. Files are kept by reference, never copied.
@MainActor
@Observable
final class ShelfService {
    private(set) var shelf = ShelfItems()
    private(set) var isVisible = false

    @ObservationIgnored private var panel: ShelfPanel?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var shake = ShakeDetector()
    /// Drag pasteboard change count when the current mouse gesture began.
    @ObservationIgnored private var gestureBaseline: Int?
    /// The shelf opened by a shake; it closes again if the drag ends with nothing dropped.
    @ObservationIgnored private var openedByShake = false
    /// The shelf opened by a Finder cut; it closes again once the paste empties it.
    @ObservationIgnored private var openedByCut = false

    func setEnabled(_ enabled: Bool) {
        if enabled, monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                let type = event.type
                let time = event.timestamp
                MainActor.assumeIsolated { self?.mouse(type, time: time) }
            }
        } else if !enabled, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    // MARK: Showing

    func toggle() {
        isVisible ? hide() : show(near: nil)
    }

    func show(near point: NSPoint?) {
        let panel = panel ?? makePanel()
        shelf.pruneMissingFiles()
        panel.place(near: point)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        openedByShake = false
        openedByCut = false
    }

    private func makePanel() -> ShelfPanel {
        let panel = ShelfPanel(content: ShelfView(service: self))
        self.panel = panel
        return panel
    }

    // MARK: Drag gesture

    private func mouse(_ type: NSEvent.EventType, time: Double) {
        let dragBoard = NSPasteboard(name: .drag)
        switch type {
        case .leftMouseDown:
            gestureBaseline = dragBoard.changeCount
            shake.reset()
        case .leftMouseDragged:
            // The window server can swallow the mouse-down (window moves), so
            // the first drag event opens the gesture instead.
            let baseline = gestureBaseline ?? dragBoard.changeCount
            gestureBaseline = baseline
            guard shake.add(time: time, x: NSEvent.mouseLocation.x),
                  !isVisible,
                  dragBoard.changeCount != baseline,
                  Self.hasDroppableContent(dragBoard)
            else { return }
            openedByShake = true
            show(near: NSEvent.mouseLocation)
        case .leftMouseUp:
            gestureBaseline = nil
            shake.reset()
            guard openedByShake else { return }
            // Give a drop on the shelf time to land before deciding.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self, self.openedByShake else { return }
                self.openedByShake = false
                if self.shelf.isEmpty { self.hide() }
            }
        default:
            break
        }
    }

    private static func hasDroppableContent(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self, NSString.self], options: nil)
    }

    // MARK: Items

    func remove(_ item: ShelfItem) {
        shelf.remove(item)
    }

    func clear() {
        shelf.removeAll()
    }

    /// Shows files cut in Finder on the shelf, so the pending cut is visible.
    func parkCut(_ urls: [URL]) {
        shelf.add(urls.map { .file($0) })
        if !isVisible {
            openedByCut = true
            show(near: nil)
        }
    }

    /// After ⌘V moved the cut files, drops them from the shelf once Finder
    /// has finished moving them away from their old path.
    func cutWasPasted(_ urls: [URL]) {
        Task { [weak self] in
            // Large or cross-volume moves take a while; stop waiting after ~10 s.
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(250))
                if !urls.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) { break }
            }
            guard let self else { return }
            self.shelf.pruneMissingFiles()
            if self.openedByCut, self.shelf.isEmpty { self.hide() }
        }
    }

    /// Reads dropped items. File and web URLs come first; plain text only
    /// when the item carries no URL.
    func accept(_ providers: [NSItemProvider]) -> Bool {
        openedByShake = false
        var accepted = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        self?.shelf.add([url.isFileURL ? .file(url) : .link(url)])
                    }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                accepted = true
                _ = provider.loadObject(ofClass: String.self) { [weak self] text, _ in
                    guard let text else { return }
                    Task { @MainActor in self?.shelf.add([.text(text)]) }
                }
            }
        }
        return accepted
    }

    /// What a drag out of the shelf carries.
    static func provider(for item: ShelfItem) -> NSItemProvider {
        switch item {
        case .file(let url):
            let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
            // Without a name, Finder names the dropped file after its type ("PDF document.pdf").
            provider.suggestedName = url.lastPathComponent
            return provider
        case .link(let url): return NSItemProvider(object: url as NSURL)
        case .text(let text): return NSItemProvider(object: text as NSString)
        }
    }
}

/// A borderless floating panel that never activates Kools, so dragging onto
/// it leaves the app you came from in front.
final class ShelfPanel: NSPanel {
    init(content: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 320),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        contentView = NSHostingView(rootView: content)
    }

    override var canBecomeKey: Bool { true }

    /// Beside the pointer (not under it, so the drop target stays visible),
    /// or at the right edge of the main screen when opened from the menu.
    func place(near point: NSPoint?) {
        let screen = point.flatMap { p in NSScreen.screens.first { $0.frame.contains(p) } } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = frame.size
        var origin: NSPoint
        if let point {
            origin = NSPoint(x: point.x + 40, y: point.y - size.height / 2)
            if origin.x + size.width > visible.maxX { origin.x = point.x - 40 - size.width }
        } else {
            origin = NSPoint(x: visible.maxX - size.width - 16, y: visible.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        setFrameOrigin(origin)
    }
}

struct ShelfView: View {
    let service: ShelfService

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(MenuBarIcon.emoji)
                Text("Shelf").font(.headline)
                if !service.shelf.isEmpty {
                    Text("\(service.shelf.items.count)").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear", systemImage: "trash") { service.clear() }
                    .labelStyle(.iconOnly)
                    .disabled(service.shelf.isEmpty)
                    .help("Remove everything from the shelf")
                Button("Close", systemImage: "xmark") { service.hide() }
                    .labelStyle(.iconOnly)
                    .help("Hide the shelf. Items stay on it.")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(WindowDragArea())

            Divider()

            ShelfItemsList(service: service)
        }
        .frame(width: 280, height: 320)
        .glassSurface(in: .rect(cornerRadius: Metrics.shelfCorner), fallback: AnyShapeStyle(.regularMaterial))
    }
}

/// The shelf's items, and a drop target for more. Used by the floating
/// shelf and the panel's Shelf tab.
struct ShelfItemsList: View {
    let service: ShelfService
    @State private var isTargeted = false

    var body: some View {
        Group {
            if service.shelf.isEmpty {
                ContentUnavailableView {
                    Label("Drop files, links or text here", systemImage: "tray.and.arrow.down")
                } description: {
                    Text("Drag them back out whenever you need them.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(service.shelf.items) { item in
                            ShelfRow(item: item) { service.remove(item) }
                        }
                    }
                    .padding(6)
                }
            }
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: Metrics.shelfCorner - 3)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(3)
            }
        }
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: $isTargeted) { providers in
            service.accept(providers)
        }
    }
}

private struct ShelfRow: View {
    let item: ShelfItem
    let remove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            icon.frame(width: 24, height: 24)
            Text(item.title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if isHovered {
                Button("Remove", systemImage: "xmark.circle.fill", action: remove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHovered ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: Metrics.tileCorner))
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onDrag { ShelfService.provider(for: item) }
        .help(helpText)
    }

    @ViewBuilder private var icon: some View {
        switch item {
        case .file(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        case .link:
            Image(systemName: "link").font(.title3).foregroundStyle(.secondary)
        case .text:
            Image(systemName: "text.alignleft").font(.title3).foregroundStyle(.secondary)
        }
    }

    private var helpText: String {
        switch item {
        case .file(let url): url.path
        case .link(let url): url.absoluteString
        case .text(let text): String(text.prefix(300))
        }
    }
}
