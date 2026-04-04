import SwiftUI

@Observable
final class AppSettings {

    static let shared = AppSettings()

    // MARK: - Draw Things Connection

    var dtHost: String {
        didSet { UserDefaults.standard.set(dtHost, forKey: "tanqueStudio.dtHost") }
    }
    var dtPort: Int {
        didSet { UserDefaults.standard.set(dtPort, forKey: "tanqueStudio.dtPort") }
    }
    var dtTransport: String {
        didSet { UserDefaults.standard.set(dtTransport, forKey: "tanqueStudio.dtTransport") }
    }
    var dtSharedSecret: String {
        didSet { UserDefaults.standard.set(dtSharedSecret, forKey: "tanqueStudio.dtSharedSecret") }
    }

    // MARK: - Storage

    var defaultImageFolder: String {
        didSet { UserDefaults.standard.set(defaultImageFolder, forKey: "tanqueStudio.defaultImageFolder") }
    }

    // MARK: - Layout

    var leftPanelWidth: CGFloat {
        didSet { UserDefaults.standard.set(leftPanelWidth, forKey: "tanqueStudio.leftPanelWidth") }
    }
    var rightPanelWidth: CGFloat {
        didSet { UserDefaults.standard.set(rightPanelWidth, forKey: "tanqueStudio.rightPanelWidth") }
    }

    // MARK: - Collection

    var selectedCollection: String? {
        didSet {
            UserDefaults.standard.set(selectedCollection, forKey: "tanqueStudio.selectedCollection")
        }
    }

    // MARK: - Init

    private init() {
        let d = UserDefaults.standard
        dtHost             = d.string(forKey: "tanqueStudio.dtHost")          ?? "127.0.0.1"
        dtPort             = d.integer(forKey: "tanqueStudio.dtPort").nonZero ?? 7859
        dtTransport        = d.string(forKey: "tanqueStudio.dtTransport")     ?? "grpc"
        dtSharedSecret     = d.string(forKey: "tanqueStudio.dtSharedSecret")  ?? ""
        defaultImageFolder = d.string(forKey: "tanqueStudio.defaultImageFolder") ?? ""
        leftPanelWidth     = d.cgFloat(forKey: "tanqueStudio.leftPanelWidth")  ?? 260
        rightPanelWidth    = d.cgFloat(forKey: "tanqueStudio.rightPanelWidth") ?? 300
        selectedCollection = d.string(forKey: "tanqueStudio.selectedCollection")
    }
}

// MARK: - Factory

extension AppSettings {
    func createDrawThingsClient() -> any DrawThingsProvider {
        switch dtTransport {
        case "http":
            return DrawThingsHTTPClient(
                host: dtHost,
                port: dtPort == 7859 ? 7860 : dtPort,  // default HTTP port if gRPC port is set
                sharedSecret: dtSharedSecret
            )
        default:
            return DrawThingsGRPCClient(host: dtHost, port: dtPort)
        }
    }
}

// MARK: - Helpers

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

private extension UserDefaults {
    func cgFloat(forKey key: String) -> CGFloat? {
        guard object(forKey: key) != nil else { return nil }
        return CGFloat(double(forKey: key))
    }
}
