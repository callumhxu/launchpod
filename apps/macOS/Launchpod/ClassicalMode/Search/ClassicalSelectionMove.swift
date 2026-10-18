import Foundation

/// Arrow-key directions for moving the selection.
nonisolated enum ClassicalNavigation: Equatable, Sendable {
    case up, down, left, right
}

/// Selection movement inside one page: up and down move a row,
/// left and right move one item, and nothing wraps to another page. Without a selection, down and
/// the forward direction select the first item; up and the backward direction the last.
nonisolated enum ClassicalSelectionMove {
    static func target(_ direction: ClassicalNavigation, selected: Int?, count: Int, columns: Int,
                       rightToLeft: Bool) -> Int? {
        guard count > 0 else { return nil }
        switch direction {
        case .up:
            guard let selected else { return count - 1 }
            return selected - columns >= 0 ? selected - columns : nil
        case .down:
            guard let selected else { return 0 }
            return selected + columns < count ? selected + columns : nil
        case .left, .right:
            if (direction == .right) != rightToLeft {
                guard let selected else { return 0 }
                return selected < count - 1 ? selected + 1 : nil
            }
            guard let selected else { return count - 1 }
            return selected > 0 ? selected - 1 : nil
        }
    }
}
