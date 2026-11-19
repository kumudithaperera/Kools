/// Decides what Finder cut and paste does with one key press.
///
/// Finder has no Cut for files. Kools turns ⌘X into Finder's own Copy and
/// remembers the pasteboard change count that copy produced. A later ⌘V
/// becomes Finder's own ⌥⌘V ("Move Item Here") only while the pasteboard
/// still holds exactly that copy, so anything copied in between turns ⌘V
/// back into a normal paste. Finder does the move itself, so name conflicts
/// and Undo behave as they always do.
public struct CutPasteRouter: Sendable {
    public struct KeyPress: Sendable {
        /// The typed character, lowercased (layout-aware, not a key code).
        public var character: String
        public var command: Bool
        /// Shift, Option or Control held. Any of these means "not our shortcut".
        public var otherModifiers: Bool

        public init(character: String, command: Bool, otherModifiers: Bool) {
            self.character = character
            self.command = command
            self.otherModifiers = otherModifiers
        }
    }

    public struct Context: Sendable {
        public var finderIsFrontmost: Bool
        /// A text field has focus (renaming a file, the search field).
        public var isEditingText: Bool
        public var pasteboardChangeCount: Int
        public var pasteboardHasFiles: Bool

        public init(finderIsFrontmost: Bool, isEditingText: Bool, pasteboardChangeCount: Int, pasteboardHasFiles: Bool) {
            self.finderIsFrontmost = finderIsFrontmost
            self.isEditingText = isEditingText
            self.pasteboardChangeCount = pasteboardChangeCount
            self.pasteboardHasFiles = pasteboardHasFiles
        }
    }

    public enum Action: Equatable, Sendable {
        /// Leave the key press alone.
        case pass
        /// Swallow ⌘X and run Finder's Copy instead.
        case copyAsCut
        /// Turn ⌘V into ⌥⌘V.
        case move
    }

    /// Change count of the pasteboard right after the last cut's copy.
    public private(set) var pendingCutChangeCount: Int?

    public init() {}

    public var hasPendingCut: Bool { pendingCutChangeCount != nil }

    /// Only plain ⌘X and ⌘V in Finder, outside text fields, are ever claimed.
    public func action(for key: KeyPress, in context: Context) -> Action {
        guard key.command, !key.otherModifiers,
              context.finderIsFrontmost, !context.isEditingText
        else { return .pass }

        switch key.character {
        case "x":
            return .copyAsCut
        case "v":
            guard let pending = pendingCutChangeCount,
                  pending == context.pasteboardChangeCount,
                  context.pasteboardHasFiles
            else { return .pass }
            return .move
        default:
            return .pass
        }
    }

    /// Call after Finder's Copy ran. `before` is the change count read before
    /// the copy; an unchanged count means Finder copied nothing (no selection),
    /// so no cut is recorded.
    public mutating func recordCut(before: Int, after: Int, hasFiles: Bool) {
        pendingCutChangeCount = (after != before && hasFiles) ? after : nil
    }

    /// A move consumes the cut, like Cut in any other app.
    public mutating func clear() {
        pendingCutChangeCount = nil
    }
}
