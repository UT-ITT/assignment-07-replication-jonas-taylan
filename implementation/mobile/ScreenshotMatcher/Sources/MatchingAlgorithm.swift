import Foundation

/// Which feature-matching algorithm the server should use for a given
/// upload. Mirrors the two implementations in implementation/server
/// (orb.py / sift.py) — the value is sent as the `algorithm` query
/// parameter on POST /upload.
enum MatchingAlgorithm: String, CaseIterable, Identifiable {
    case orb
    case sift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .orb: return "ORB"
        case .sift: return "SIFT"
        }
    }
}
