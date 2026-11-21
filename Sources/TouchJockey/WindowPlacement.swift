import AppKit

/// Puts the main window on the laptop's own screen, in full screen, at launch.
enum WindowPlacement {
    /// The Mac's built-in display, if there is one (nil on desktops or with the lid closed).
    static var builtInScreen: NSScreen? {
        NSScreen.screens.first { screen in
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(CGDirectDisplayID(n.uint32Value)) != 0
        }
    }

    /// Moves the window to the built-in screen (or keeps it where it is if there isn't one)
    /// and enters full screen. Runs once the window exists.
    static func fullScreenOnLaptop() {
        DispatchQueue.main.async {
            // The largest visible window that can be main is the app window (SwiftUI can add small helper windows).
            guard let window = NSApp.windows.filter({ $0.isVisible && $0.canBecomeMain })
                .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                // The window isn't up yet; try again shortly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { fullScreenOnLaptop() }
                return
            }
            window.collectionBehavior.insert(.fullScreenPrimary)
            if window.styleMask.contains(.fullScreen) { return }
            if let screen = builtInScreen, window.screen != screen {
                window.setFrame(screen.visibleFrame, display: true)
            }
            // macOS ignores a full-screen request made while the window is still settling at launch,
            // so give it a moment, and check again before toggling.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
            }
        }
    }
}
