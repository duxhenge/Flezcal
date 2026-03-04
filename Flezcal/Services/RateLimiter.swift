import Foundation

/// Lightweight client-side rate limiter to prevent accidental rapid-fire submissions.
/// Uses per-action cooldowns — not a replacement for server-side security rules.
actor RateLimiter {
    static let shared = RateLimiter()

    private var lastActionTimes: [String: Date] = [:]

    /// Returns true if the action is allowed (cooldown has elapsed).
    /// Records the current time if allowed.
    func allowAction(_ key: String, cooldown: TimeInterval = 2.0) -> Bool {
        let now = Date()
        if let last = lastActionTimes[key],
           now.timeIntervalSince(last) < cooldown {
            return false
        }
        lastActionTimes[key] = now
        return true
    }

    /// Tracks Brave Search API calls per session for quota awareness.
    private var braveCallCount = 0
    private let braveSessionLimit = 50  // Conservative per-session limit

    func recordBraveCall() {
        braveCallCount += 1
    }

    func braveCallsRemaining() -> Int {
        max(0, braveSessionLimit - braveCallCount)
    }

    func canMakeBraveCall() -> Bool {
        braveCallCount < braveSessionLimit
    }
}
