import Foundation

/// Turns "when did we last scan" into the short phrase the results header shows.
///
/// Deliberately its own value-in, string-out type rather than a `Date.formatted`
/// call at the call site, for two reasons. First, it is the one piece of the
/// staleness indicator worth testing, and a pure function is trivial to test.
/// Second, `RelativeDateTimeFormatter` is lovely for prose but too chatty for a
/// caption that sits next to a scan summary: we want "2m ago", not "2 minutes
/// ago", and certainly not "in 0 seconds" when the clock jitters.
///
/// The units stop at days on purpose. If your scan is a week old the exact number
/// stops mattering; what matters is that it is ancient, and "8d ago" says that
/// just as well as any calendar date would.
enum ScanTimeFormatter {

    /// Below this, a scan is fresh enough that a number would be noise.
    private static let justNowThreshold: TimeInterval = 45

    /// Short relative phrase for a scan that happened at `date`, as of `now`.
    ///
    /// Clock changes and daylight saving can hand us a scan that appears to be in
    /// the future. Rather than print a negative age we treat it as fresh, since
    /// "just now" is both harmless and very nearly true.
    static func relativeDescription(since date: Date, now: Date = Date()) -> String {
        let age = now.timeIntervalSince(date)
        guard age >= justNowThreshold else { return "just now" }

        let minutes = Int((age / 60).rounded())
        if minutes < 60 { return "\(max(1, minutes))m ago" }

        let hours = Int((age / 3600).rounded())
        if hours < 24 { return "\(max(1, hours))h ago" }

        let days = Int((age / 86_400).rounded())
        return "\(max(1, days))d ago"
    }

    /// How often the header should refresh the phrase to stay honest.
    ///
    /// A scan under an hour old is measured in minutes, so a ticker slower than a
    /// minute would let the label lie. Past that the label barely moves, but the
    /// panel is rarely open long enough for the extra ticks to matter, so we keep
    /// one simple interval instead of a sliding one.
    static let refreshInterval = Duration.seconds(30)
}
