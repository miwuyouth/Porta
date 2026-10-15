import Foundation

public final class YamuxSession: @unchecked Sendable {
    private let underlying: any AsyncConnection
    private let lock = SafeLock()
    private var nextStreamID: UInt32 = 1 // Clients use odd numbers
    private var streams: [UInt32: YamuxStream] = [:]
    private var isClosed = false
    private var receiveTask: Task<Void, Never>?

    public init(underlying: any AsyncConnection) {
        self.underlying = underlying
        startReceiveLoop()
    }

    deinit {
        close()
    }

    public func openStream() async throws -> YamuxStream {
        let stream: YamuxStream = try lock.withLock {
            guard !isClosed else {
                throw AsyncConnectionError.closed
            }

            let streamID = nextStreamID
            nextStreamID += 2
            let s = YamuxStream(id: streamID, session: self)
            streams[streamID] = s
            return s
        }

        // Send SYN frame to open stream on remote side (Yamux standard)
        try await sendFrame(header: YamuxHeader(
            type: .windowUpdate,
            flags: .syn,
            streamID: stream.id,
            length: 0
        ), payload: nil)

        return stream
    }

    internal func sendDataFrame(streamID: UInt32, data: Data, flags: YamuxFlags) async throws {
        let header = YamuxHeader(
            type: .data,
            flags: flags,
            streamID: streamID,
            length: UInt32(data.count)
        )
        try await sendFrame(header: header, payload: data)
    }

    internal func sendWindowUpdate(streamID: UInt32, delta: UInt32) async throws {
        let header = YamuxHeader(
            type: .windowUpdate,
            flags: [],
            streamID: streamID,
            length: delta
        )
        try await sendFrame(header: header, payload: nil)
    }

    internal func sendStreamClose(streamID: UInt32) async throws {
        let header = YamuxHeader(
            type: .data,
            flags: .fin,
            streamID: streamID,
            length: 0
        )
        try await sendFrame(header: header, payload: nil)

        lock.withLock {
            _ = streams.removeValue(forKey: streamID)
        }
    }

    private func sendFrame(header: YamuxHeader, payload: Data?) async throws {
        let closed = lock.withLock { isClosed }
        guard !closed else { throw AsyncConnectionError.closed }

        var frameData = header.encode()
        if let payload = payload, !payload.isEmpty {
            frameData.append(payload)
        }

        // Ensure serialized writes so frames don't interleave
        try await underlying.write(frameData)
    }

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while let self = self, !Task.isCancelled {
                do {
                    let headerData = try await self.underlying.read(exactCount: YamuxHeader.headerSize)
                    guard let header = YamuxHeader.decode(from: headerData) else {
                        break
                    }

                    var payload: Data = Data()
                    if header.length > 0 && header.type == .data {
                        payload = try await self.underlying.read(exactCount: Int(header.length))
                    }

                    self.handleIncomingFrame(header: header, payload: payload)
                } catch {
                    break
                }
            }
            self?.close()
        }
    }

    private func handleIncomingFrame(header: YamuxHeader, payload: Data) {
        let stream = lock.withLock {
            streams[header.streamID]
        }

        switch header.type {
        case .data:
            if let stream = stream {
                if !payload.isEmpty {
                    stream.pushData(payload)
                }
                if header.flags.contains(.fin) || header.flags.contains(.rst) {
                    stream.handleRemoteClose()
                    lock.withLock {
                        _ = streams.removeValue(forKey: header.streamID)
                    }
                }
            }
        case .windowUpdate:
            stream?.updateSendWindow(delta: header.length)
            if header.flags.contains(.fin) || header.flags.contains(.rst) {
                stream?.handleRemoteClose()
                lock.withLock {
                    _ = streams.removeValue(forKey: header.streamID)
                }
            }
        case .ping:
            // Echo ping back with ACK if it's a request
            if !header.flags.contains(.ack) {
                Task { [weak self] in
                    try? await self?.sendFrame(header: YamuxHeader(
                        type: .ping,
                        flags: .ack,
                        streamID: 0,
                        length: header.length
                    ), payload: nil)
                }
            }
        case .goAway:
            close()
        }
    }

    public func close() {
        let allStreams = lock.withLock { () -> [YamuxStream] in
            guard !isClosed else { return [] }
            isClosed = true
            let s = Array(streams.values)
            streams.removeAll()
            return s
        }

        receiveTask?.cancel()
        for stream in allStreams {
            stream.handleRemoteClose()
        }
        underlying.close()
    }
}
