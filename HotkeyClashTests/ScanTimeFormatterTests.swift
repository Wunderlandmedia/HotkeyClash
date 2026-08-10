import Foundation
import Testing
@testable import HotkeyClash

/// Tests for the staleness label in the results header.
///
/// The boundaries are the interesting part: the label has to switch units without
/// ever showing "0m ago" or "60m ago", and it must not go strange when the clock
/// moves backwards under it. Time is passed in explicitly rather than read from
/// the wall clock, so none of this can go flaky at an inconvenient hour.
@Suite("Scan time formatter")
struct ScanTimeFormatterTests {

    /// Fixed reference point so nothing here depends on when the suite runs.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func phrase(secondsAgo: TimeInterval) -> String {
        ScanTimeFormatter.relativeDescription(since: now.addingTimeInterval(-secondsAgo), now: now)
    }

    // MARK: - Fresh

    @Test("A recent scan reads as just now", arguments: [0.0, 20.0, 44.0])
    func fresh(secondsAgo: TimeInterval) {
        #expect(phrase(secondsAgo: secondsAgo) == "just now")
    }

    @Test("A scan dated in the future is treated as fresh, not negative")
    func clockWentBackwards() {
        // Daylight saving or an NTP correction can hand us this. "in -3m" would be
        // nonsense on screen, and "just now" is very nearly true anyway.
        #expect(phrase(secondsAgo: -180) == "just now")
    }

    // MARK: - Units

    @Test("Past the fresh window it counts minutes, never zero", arguments: [
        (45.0, "1m ago"),
        (60.0, "1m ago"),
        (120.0, "2m ago"),
        (1500.0, "25m ago")
    ])
    func minutes(secondsAgo: TimeInterval, expected: String) {
        #expect(phrase(secondsAgo: secondsAgo) == expected)
    }

    @Test("An hour in, it switches to hours rather than showing 60m", arguments: [
        (3600.0, "1h ago"),
        (7200.0, "2h ago"),
        (82_800.0, "23h ago")
    ])
    func hours(secondsAgo: TimeInterval, expected: String) {
        #expect(phrase(secondsAgo: secondsAgo) == expected)
    }

    @Test("A day in, it switches to days", arguments: [
        (86_400.0, "1d ago"),
        (86_400.0 * 3, "3d ago"),
        (86_400.0 * 30, "30d ago")
    ])
    func days(secondsAgo: TimeInterval, expected: String) {
        #expect(phrase(secondsAgo: secondsAgo) == expected)
    }

    // MARK: - Sweep

    @Test("No point in the first day produces a zero or rolled-over count")
    func unitBoundariesHold() {
        // Walking the whole day is the cheap way to catch a rounding change that
        // quietly reintroduces "0m ago" or lets "60m ago" through.
        for seconds in stride(from: 45.0, through: 86_400.0, by: 37.0) {
            let text = phrase(secondsAgo: seconds)
            #expect(text.hasPrefix("0") == false, "Zero count at \(seconds)s: \(text)")
            #expect(text != "60m ago", "Should have rolled over to hours at \(seconds)s")
            #expect(text != "24h ago", "Should have rolled over to days at \(seconds)s")
        }
    }
}
