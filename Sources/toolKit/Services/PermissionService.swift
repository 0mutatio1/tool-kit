import CoreGraphics
import Foundation

@MainActor
struct PermissionService {
    private static var hasScreenCapturePermission = false

    enum PermissionError: LocalizedError {
        case denied

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Screen Recording permission is required to capture a screen region. Open System Settings > Privacy & Security > Screen Recording and allow this app, then try again."
            }
        }
    }

    func ensureScreenCapturePermission() throws {
        if Self.hasScreenCapturePermission {
            return
        }

        if CGPreflightScreenCaptureAccess() {
            Self.hasScreenCapturePermission = true
            return
        }

        if CGRequestScreenCaptureAccess() {
            Self.hasScreenCapturePermission = true
            return
        }

        throw PermissionError.denied
    }
}
