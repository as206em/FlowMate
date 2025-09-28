import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("AppDelegate: 🚀 Application did finish launching")
        // Set activation policy for menu bar app to allow windows to receive focus
        NSApp.setActivationPolicy(.accessory)
        NSLog("AppDelegate: ⚙️ Set activation policy to accessory")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        NSLog("AppDelegate: ⚠️ Application will terminate")
    }
    
    func applicationDidReceiveMemoryWarning(_ notification: Notification) {
        NSLog("AppDelegate: ⚠️ Application received memory warning")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSLog("AppDelegate: 🪟 Application should terminate after last window closed: false")
        return false
    }
    
    func applicationWillHide(_ notification: Notification) {
        NSLog("AppDelegate: 🕶️ Application will hide")
    }
    
    func applicationDidHide(_ notification: Notification) {
        NSLog("AppDelegate: 🕶️ Application did hide")
    }
    
    func applicationWillUnhide(_ notification: Notification) {
        NSLog("AppDelegate: 🕶️ Application will unhide")
    }
    
    func applicationDidUnhide(_ notification: Notification) {
        NSLog("AppDelegate: 🕶️ Application did unhide")
    }
}
