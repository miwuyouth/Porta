import Foundation

public enum StreamBridge {
    /// Bridges two connections asynchronously, forwarding data bidirectionally
    /// until either connection closes or encounters an error.
    public static func bridge(
        _ connA: any AsyncConnection,
        _ connB: any AsyncConnection,
        bufferSize: Int = 32 * 1024
    ) async {
        await withTaskGroup(of: Void.self) { group in
            // Forward connA -> connB
            group.addTask {
                await pump(from: connA, to: connB, bufferSize: bufferSize)
            }

            // Forward connB -> connA
            group.addTask {
                await pump(from: connB, to: connA, bufferSize: bufferSize)
            }

            // Once the first pump direction finishes, close both connections to tear down
            _ = await group.next()
            connA.close()
            connB.close()
            group.cancelAll()
        }
    }

    private static func pump(
        from source: any AsyncConnection,
        to destination: any AsyncConnection,
        bufferSize: Int
    ) async {
        while !source.isClosed && !destination.isClosed && !Task.isCancelled {
            do {
                let data = try await source.read(upToCount: bufferSize)
                if data.isEmpty {
                    break // EOF
                }
                try await destination.write(data)
            } catch {
                break
            }
        }
    }
}
