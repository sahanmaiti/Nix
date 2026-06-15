import ServiceManagement
import os.log

enum LoginItemService {
    
    private static let logger = Logger(
        subsystem: "com.saha.Nix",
        category: "LoginItemService"
    )
    
    //MARK:- Current State
    ///Returns true if Nix is currently registered to lauch at login.
    
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    
    //MARK:- Register / Unregister
    ///Sets Nix's  launch-at-login state.
    
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                logger.info("Login item registered - Nix will launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("Login item unregistered - Nix will not launch at login")
            }
        } catch {
            logger.error("Login item \(enabled ? "registration" : "unregistration") failed: \(error.localizedDescription)")
        }
    }
}
