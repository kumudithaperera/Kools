import AppKit
import KoolsCore
import SwiftUI

/// The floating clipboard shelf.
struct ClipboardView: View {
    let service: ClipboardService

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: ToolItem.clipboard.symbol).foregroundStyle(.secondary)
                Text("Clipboard").font(.headline)
                Spacer()
                Button("Clear History", systemImage: "trash") { service.clearHistory() }
                    .labelStyle(.iconOnly)
                    .disabled(service.history.isEmpty)
                    .help("Clear the copy history. Notes stay.")
                Button("Close", systemImage: "xmark") { service.hide() }
                    .labelStyle(.iconOnly)
                    .help("Hide the clipboard")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ClipboardBrowser(service: service)
                .padding(8)
        }
        .frame(width: 280, height: 320)
        .glassSurface(in: .rect(cornerRadius: Metrics.shelfCorner), fallback: AnyShapeStyle(.regularMaterial))
    }
}

/// History and Notes behind one switch. Clicking a row copies it.
struct ClipboardBrowser: View {
    let service: ClipboardService

    var body: some View {
        @Bindable var service = service
        VStack(spacing: 8) {
            Picker("List", selection: $service.tab) {
                Text("History \(service.history.entries.count)").tag(ClipboardTab.history)
                Text("Notes \(service.notes.notes.count)").tag(ClipboardTab.notes)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch service.tab {
            case .history: HistoryList(entries: service.history.entries, copy: service.copy(_:), remove: service.remove(_:))
            case .notes: NotesList(service: service)
            }
        }
    }
}

// MARK: History

private struct HistoryList: View {
    let entries: [ClipboardEntry]
    let copy: (String) -> Void
    let remove: (ClipboardEntry) -> Void

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView {
                Label("Nothing copied yet", systemImage: "doc.on.clipboard")
            } description: {
                Text("What you copy shows up here for 12 hours.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(entries) { entry in
                        HistoryRow(entry: entry, copy: { copy(entry.text) }, remove: { remove(entry) })
                    }
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: ClipboardEntry
    let copy: () -> Void
    let remove: () -> Void
    @State private var isHovered = false
    @State private var justCopied = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.preview).lineLimit(2).font(.callout)
                Text("\(Text(entry.copiedAt, style: .relative)) ago").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if justCopied {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if isHovered {
                Button("Remove", systemImage: "xmark.circle.fill", action: remove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: Metrics.tileCorner))
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture { flash(copy) }
        .help(String(entry.text.prefix(300)))
    }

    private func flash(_ action: () -> Void) {
        action()
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            justCopied = false
        }
    }
}

// MARK: Notes

private struct NotesList: View {
    let service: ClipboardService
    @State private var draft = ""
    @State private var isFull = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                TextField("Add a note", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", systemImage: "plus.circle.fill", action: add)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if isFull {
                Text("Note limit reached. Delete one to add another.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if service.notes.isEmpty {
                ContentUnavailableView {
                    Label("No notes yet", systemImage: "note.text")
                } description: {
                    Text("Keep short text you paste often. Notes stay until you delete them.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(service.notes.notes) { note in
                        NoteRow(note: note, service: service)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                    }
                    .onMove { service.moveNotes(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func add() {
        guard service.addNote(draft) else {
            isFull = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return
        }
        draft = ""
        isFull = false
    }
}

private struct NoteRow: View {
    let note: ClipboardNote
    let service: ClipboardService
    @State private var isHovered = false
    @State private var justCopied = false
    @State private var isEditing = false
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            if isEditing {
                TextField("Note", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commit)
                    .onExitCommand { isEditing = false }
                Button("Save", systemImage: "checkmark.circle.fill", action: commit)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            } else {
                Text(note.text).lineLimit(2).font(.callout)
                Spacer(minLength: 0)
                if justCopied {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if isHovered {
                    Group {
                        Button("Edit", systemImage: "pencil") {
                            text = note.text
                            isEditing = true
                        }
                        Button("Delete", systemImage: "xmark.circle.fill") { service.removeNote(note) }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: Metrics.tileCorner))
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture {
            guard !isEditing else { return }
            service.copy(note.text)
            justCopied = true
            Task {
                try? await Task.sleep(for: .seconds(1))
                justCopied = false
            }
        }
        .help(String(note.text.prefix(300)))
    }

    private func commit() {
        service.updateNote(note, text: text)
        isEditing = false
    }
}

// MARK: Paste button

/// The small button shown at the text field you're typing in.
struct PasteButtonView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: ToolItem.clipboard.symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassSurface(in: .circle, interactive: true, fallback: AnyShapeStyle(.regularMaterial))
        .help("Paste from the clipboard history or your notes")
    }
}

/// What the paste button opens: the same two lists, where a click pastes.
struct PasteMenuView: View {
    let service: ClipboardService
    let paste: (String) -> Void
    @State private var tab = ClipboardTab.history

    var body: some View {
        VStack(spacing: 8) {
            Picker("List", selection: $tab) {
                Text("History").tag(ClipboardTab.history)
                Text("Notes").tag(ClipboardTab.notes)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                LazyVStack(spacing: 2) {
                    switch tab {
                    case .history:
                        ForEach(service.history.entries) { entry in
                            PasteRow(text: entry.text, title: entry.preview, paste: paste)
                        }
                    case .notes:
                        ForEach(service.notes.notes) { note in
                            PasteRow(text: note.text, title: ClipboardEntry.preview(of: note.text), paste: paste)
                        }
                    }
                }
            }
            .overlay {
                if isEmpty {
                    Text(tab == .history ? "Nothing copied in the last 12 hours" : "No notes yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .frame(width: 260, height: 240)
        .glassSurface(in: .rect(cornerRadius: Metrics.corner), fallback: AnyShapeStyle(.regularMaterial))
    }

    private var isEmpty: Bool {
        tab == .history ? service.history.isEmpty : service.notes.isEmpty
    }
}

private struct PasteRow: View {
    let text: String
    let title: String
    let paste: (String) -> Void
    @State private var isHovered = false

    var body: some View {
        Text(title)
            .lineLimit(2)
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: Metrics.tileCorner))
            .contentShape(.rect)
            .onHover { isHovered = $0 }
            .onTapGesture { paste(text) }
    }
}
