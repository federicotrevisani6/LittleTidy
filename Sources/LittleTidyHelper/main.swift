import Foundation
import LittleTidyCore

final class HelperService: NSObject, SystemCareHelperProtocol {
    private let analyzer = SystemCareAnalyzer(runner: BoundedCommandRunner(timeout: 45))
    func measureSystemStorage(reply: @escaping @Sendable (Data?, String?) -> Void) {
        Task { [analyzer] in
            do {
                let result = try await analyzer.storage(locations: SystemCareAnalyzer.systemLocations)
                reply(try JSONEncoder().encode(result), nil)
            } catch { reply(nil, error.localizedDescription) }
        }
    }
    func performMaintenance(_ operation: String, reply: @escaping @Sendable (String?, String?) -> Void) {
        guard let operation = MaintenanceOperation(rawValue: operation) else {
            reply(nil, "Unsupported maintenance operation."); return
        }
        Task { [analyzer] in
            do { reply(try await analyzer.maintenance(operation), nil) }
            catch { reply(nil, error.localizedDescription) }
        }
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Match both the publisher and the exact application identity. launchd
        // supplies peer credentials; callers cannot supply a path or executable.
        guard connection.effectiveUserIdentifier >= 501 else { return false }
        connection.setCodeSigningRequirement(SystemCareHelperIdentity.appRequirement)
        connection.exportedInterface = NSXPCInterface(with: SystemCareHelperProtocol.self)
        connection.exportedObject = HelperService()
        connection.resume()
        return true
    }
}
let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: SystemCareHelperIdentity.service)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
