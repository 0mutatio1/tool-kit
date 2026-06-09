import CoreGraphics
import Foundation

struct PermissionService {
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
        if CGPreflightScreenCaptureAccess() {
            return
        }

        if CGRequestScreenCaptureAccess() {
            return
        }

        throw PermissionError.denied
    }
}
