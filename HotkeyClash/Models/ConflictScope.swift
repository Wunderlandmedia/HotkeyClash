import Foundation

/// The severity scope for the results list: which conflicts the sidebar shows.
///
/// Kept as a standalone value type (rather than view state logic) so the
/// matching rules are testable next to the classification logic they build on.
enum ConflictScope: String, CaseIterable, Identifiable {
    /// Everything the scan found, real conflicts and app menu overlaps alike.
    case all
    /// Only always-on clashes: at least one global hotkey is involved.
    case realConflicts
    /// Only definite clashes: two or more global hotkeys on the same combo.
    case definiteOnly

    var id: Self { self }

    /// Label shown in the scope picker.
    var label: String {
        switch self {
        case .all: "All"
        case .realConflicts: "Real conflicts"
        case .definiteOnly: "Definite only"
        }
    }

    /// Message for the sidebar when this scope filters everything out. Framed as
    /// good news, because an empty narrowed list means nothing bites.
    var emptyMessage: String {
        switch self {
        case .all: "No conflicts"
        case .realConflicts: "No real conflicts"
        case .definiteOnly: "No definite conflicts"
        }
    }

    /// Whether a conflict belongs in this scope.
    func matches(_ conflict: Conflict) -> Bool {
        switch self {
        case .all:
            true
        case .realConflicts:
            conflict.category == .realConflict
        case .definiteOnly:
            conflict.severity == .definite
        }
    }
}
