import Foundation
import FirebaseCrashlytics

/// Lightweight wrapper for Crashlytics non-fatal error reporting.
///
/// Usage:
///   `CrashReporter.record(error, context: "SpotService.loadSpots")`
///
/// This avoids importing FirebaseCrashlytics in every service file and
/// centralizes the `#if DEBUG` print logic.
enum CrashReporter {

    /// Records a non-fatal error to Crashlytics with optional context.
    /// In DEBUG builds, also prints to the console.
    static func record(_ error: Error, context: String? = nil) {
        if let context {
            Crashlytics.crashlytics().setCustomValue(context, forKey: "errorContext")
        }
        Crashlytics.crashlytics().record(error: error)

        #if DEBUG
        let prefix = context.map { "[\($0)] " } ?? ""
        print("CrashReporter: \(prefix)\(error.localizedDescription)")
        #endif
    }

    /// Records a non-fatal error from a string message (when no Error is available).
    static func log(_ message: String, context: String? = nil) {
        let nsError = NSError(
            domain: AppConstants.bundleID,
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        record(nsError, context: context)
    }

    /// Adds a breadcrumb log line to Crashlytics (visible in crash reports).
    /// Use for key user actions — e.g. "Tapped add spot", "Sign in succeeded".
    static func breadcrumb(_ message: String) {
        Crashlytics.crashlytics().log(message)
        #if DEBUG
        print("CrashReporter breadcrumb: \(message)")
        #endif
    }
}
