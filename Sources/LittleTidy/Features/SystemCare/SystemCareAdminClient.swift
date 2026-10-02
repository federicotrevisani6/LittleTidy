import Foundation
import LittleTidyCore
import ServiceManagement

@MainActor
final class SystemCareAdminClient {
    var payloadAvailable: Bool {
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents")
        return FileManager.default.fileExists(atPath: contents.appendingPathComponent("Library/LaunchDaemons/\(SystemCareHelperIdentity.plist)").path)
            && FileManager.default.isExecutableFile(atPath: contents.appendingPathComponent("Library/HelperTools/LittleTidyHelper").path)
    }
    var status: SMAppService.Status { service.status }
    private var service: SMAppService { .daemon(plistName: SystemCareHelperIdentity.plist) }
    func register() throws { try service.register() }
    func unregister() async throws { try await service.unregister() }
    func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }

    func measurements() async throws -> [StorageMeasurement] {
        let data: Data = try await request { proxy, completion in
            proxy.measureSystemStorage { data, error in
                if let data { completion(.success(data)) }
                else { completion(.failure(AdminError.message(error ?? "No measurement was returned."))) }
            }
        }
        return try JSONDecoder().decode([StorageMeasurement].self, from: data)
    }
    func maintenance(_ operation: MaintenanceOperation) async throws -> String {
        try await request { proxy, completion in
            proxy.performMaintenance(operation.rawValue) { output, error in
                if let output { completion(.success(output)) }
                else { completion(.failure(AdminError.message(error ?? "No result was returned."))) }
            }
        }
    }
    private func request<Value: Sendable>(send: (any SystemCareHelperProtocol, @escaping @Sendable (Result<Value, Error>) -> Void) -> Void) async throws -> Value {
        guard status == .enabled else { throw AdminError.message("Enable Administrator Access and approve LittleTidy in Login Items & Extensions.") }
        let connection = NSXPCConnection(machServiceName: SystemCareHelperIdentity.service, options: .privileged)
        connection.setCodeSigningRequirement(SystemCareHelperIdentity.helperRequirement)
        connection.remoteObjectInterface = NSXPCInterface(with: SystemCareHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        let gate = ReplyGate<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                connection.invalidationHandler = { gate.finish(.failure(AdminError.message("Administrator service disconnected."))) }
                connection.interruptionHandler = { gate.finish(.failure(AdminError.message("Administrator service was interrupted."))) }
                let proxy = connection.remoteObjectProxyWithErrorHandler { gate.finish(.failure($0)) }
                guard let proxy = proxy as? any SystemCareHelperProtocol else {
                    gate.finish(.failure(AdminError.message("Administrator service is unavailable."))); return
                }
                send(proxy) { gate.finish($0) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 360) {
                    gate.finish(.failure(AdminError.message("Administrator operation timed out.")))
                }
            }
        } onCancel: { gate.finish(.failure(CancellationError())) }
    }
}
private enum AdminError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { value } else { nil } }
}
/// XPC errors, cancellation, timeout, and replies can race. Resume exactly once.
private final class ReplyGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    func install(_ value: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result { lock.unlock(); value.resume(with: result) }
        else { continuation = value; lock.unlock() }
    }
    func finish(_ value: Result<Value, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let pending = continuation; continuation = nil
        lock.unlock()
        pending?.resume(with: value)
    }
}
