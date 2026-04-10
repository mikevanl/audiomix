import Foundation
import Network

public enum IPCError: Error, LocalizedError {
    case appNotRunning
    case connectionFailed(String)
    case timeout
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .appNotRunning: return "AudioMix app is not running. Start it first."
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .timeout: return "Request timed out."
        case .invalidResponse: return "Invalid response from AudioMix."
        }
    }
}

public final class IPCClient: Sendable {
    private let socketPath: String

    public init(socketPath: String = IPCConstants.socketPath) {
        self.socketPath = socketPath
    }

    public func send(_ request: IPCRequest) async throws -> IPCResponse {
        let endpoint = NWEndpoint.unix(path: socketPath)
        let connection = NWConnection(to: endpoint, using: .tcp)

        return try await withThrowingTaskGroup(of: IPCResponse.self) { group in
            group.addTask {
                try await self.performRequest(connection: connection, request: request)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw IPCError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            connection.cancel()
            return result
        }
    }

    private func performRequest(connection: NWConnection, request: IPCRequest) async throws -> IPCResponse {
        try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    self.sendAndReceive(connection: connection, request: request, continuation: continuation)
                case .failed(let error):
                    continuation.resume(throwing: IPCError.connectionFailed(error.localizedDescription))
                case .waiting:
                    continuation.resume(throwing: IPCError.appNotRunning)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    private func sendAndReceive(connection: NWConnection, request: IPCRequest,
                                continuation: CheckedContinuation<IPCResponse, any Error>) {
        guard var data = try? JSONEncoder().encode(request) else {
            continuation.resume(throwing: IPCError.invalidResponse)
            return
        }
        data.append(0x0A) // newline

        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                continuation.resume(throwing: IPCError.connectionFailed(error.localizedDescription))
                return
            }

            self.receiveResponse(connection: connection, buffer: Data(), continuation: continuation)
        })
    }

    private func receiveResponse(connection: NWConnection, buffer: Data,
                                 continuation: CheckedContinuation<IPCResponse, any Error>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, error in
            if let error {
                continuation.resume(throwing: IPCError.connectionFailed(error.localizedDescription))
                return
            }

            var accumulated = buffer
            if let content { accumulated.append(content) }

            if accumulated.contains(0x0A) {
                let lineEnd = accumulated.firstIndex(of: 0x0A)!
                let lineData = accumulated[accumulated.startIndex..<lineEnd]
                guard let response = try? JSONDecoder().decode(IPCResponse.self, from: lineData) else {
                    continuation.resume(throwing: IPCError.invalidResponse)
                    return
                }
                continuation.resume(returning: response)
            } else {
                self.receiveResponse(connection: connection, buffer: accumulated, continuation: continuation)
            }
        }
    }
}
