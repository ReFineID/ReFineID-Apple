#if canImport(ReFineIDRapp)
import Foundation

/// Adapts an existing platform transport without giving it any RAPP semantic
/// authority. The closures must preserve frame boundaries and return only after
/// the frame was released to the underlying transport.
public actor RappClosureFrameTransport: RappFrameTransport {
    public typealias Sender = @Sendable (Data) async throws -> Void
    public typealias Closer = @Sendable () async -> Void

    private let sender: Sender
    private let closer: Closer
    private var isClosed = false

    public init(sender: @escaping Sender, closer: @escaping Closer) {
        self.sender = sender
        self.closer = closer
    }

    public func send(_ frame: Data) async throws {
        guard !isClosed else { throw CancellationError() }
        try await sender(frame)
    }

    public func close() async {
        guard !isClosed else { return }
        isClosed = true
        await closer()
    }
}
#endif
