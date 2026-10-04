import Foundation

/// Where AnyDrag shows its icon (issue #52). The app has no main window — the
/// Settings window is the only one — so at least one of the two surfaces must
/// stay on, otherwise there is no way left to reach the app. That is why this
/// is a three-way choice and not two independent toggles.
enum AppIconMode: String, CaseIterable {
    case menuBar = "menuBar"   // the default; what every release before #52 did
    case dock    = "dock"
    case both    = "both"

    var showsMenuBarIcon: Bool { self != .dock }
    var showsDockIcon: Bool    { self != .menuBar }

    var titleKey: String {
        switch self {
        case .menuBar: return "appIcon.menuBar"
        case .dock:    return "appIcon.dock"
        case .both:    return "appIcon.both"
        }
    }
}

extension Notification.Name {
    /// Posted by `Preferences.setAppIconMode` after the value is persisted.
    static let anyDragAppIconModeChanged = Notification.Name("AnyDragAppIconModeChanged")
}
