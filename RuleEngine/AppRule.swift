import Foundation

struct AppRule: Codable, Identifiable {
    
    // MARK: - Identifiable
    var id: String{ bundleIdentifier }
    
    // MARK: - Core Data
    var bundleIdentifier: String
    var aappName: String
    var behavior: AppBehavior
    var gracePeriodSeconds: Int
    var isWhitelisted: Bool
    var lastModified: Date
    
    // MARK: - Initializer
    init(
        bundleIdentifier: String,
        appName: String,
        behavior: AppBehavior = .quit,
        gracePeriodSeconds: Int = -1,
        isWhilisted: Bool = false
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.aappName = appName
        self.behavior = behavior
        self.gracePeriodSeconds = gracePeriodSeconds
        self.isWhitelisted = isWhilisted
        self.lastModified = Date()
    }
}
