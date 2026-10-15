import Foundation

public struct FRPServer: Identifiable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var serverAddr: String
    public var serverPort: Int
    public var token: String
    public var transportProtocol: String
    public var tlsEnable: Bool
    public var isDefault: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        serverAddr: String = "127.0.0.1",
        serverPort: Int = 7000,
        token: String = "",
        transportProtocol: String = "tcp",
        tlsEnable: Bool = false,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.serverAddr = serverAddr
        self.serverPort = serverPort
        self.token = token
        self.transportProtocol = transportProtocol
        self.tlsEnable = tlsEnable
        self.isDefault = isDefault
    }
}
