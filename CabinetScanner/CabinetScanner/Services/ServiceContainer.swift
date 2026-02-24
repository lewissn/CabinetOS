import Foundation

/// Central service locator — switch between mock and live by changing Configuration.apiMode
final class ServiceContainer {
    static let shared = ServiceContainer()

    lazy var api: APIServiceProtocol = {
        switch Configuration.apiMode {
        case .mock:
            return MockAPIService()
        case .live:
            return LiveAPIService()
        }
    }()

    private init() {}
}
