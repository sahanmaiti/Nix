import SwiftUI

@main
struct NixApp: App {
    
    //Wires AppKit delegate into SwiftUI App lifecycle
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        
        //MenuBarExtra = menu bar icon + dropdown panel
        MenuBarExtra("Nix", systemImage: "xmark.circle") {
            Text("Nix is running").padding()
            Divider()
            Button("Quit Nix") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.window)  //floating panel, not inline menu
    }
}
