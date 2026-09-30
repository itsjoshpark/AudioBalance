import Foundation

/// Pure decisions about balance values, kept free of CoreAudio so they can be unit tested.
nonisolated enum BalancePolicy {
    static let center: Float = 0.5

    /// Differences smaller than this are treated as balanced, so floating-point noise and
    /// sub-perceptible drift never trigger a write.
    static let tolerance: Float = 0.02

    /// How long to wait after the last change notification before checking. Collapses bursts of
    /// notifications (e.g. while a slider is dragged) into a single check.
    static let debounce: Duration = .milliseconds(100)

    static func needsCorrection(current: Float, lock: Float, tolerance: Float = tolerance) -> Bool {
        abs(current - lock) >= tolerance
    }

    /// Snaps values within ``tolerance`` of center to exactly center, so a dragged slider can
    /// land on center without pixel-perfect aim.
    static func snapped(_ value: Float) -> Float {
        abs(value - center) < tolerance ? center : clamped(value)
    }

    static func clamped(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    /// A human-readable balance such as "Centered", "20% Left" or "35% Right".
    static func describe(_ value: Float) -> String {
        let offset = Int(((clamped(value) - center) * 200).rounded())
        switch offset {
        case 0: return String(localized: "Centered")
        case ..<0: return String(localized: "\(-offset)% Left")
        default: return String(localized: "\(offset)% Right")
        }
    }
}
