import AppKit

/// Sets the macOS desktop wallpaper on all screens.
struct WallpaperService {

    func setWallpaper(_ imageURL: URL) throws {
        let workspace = NSWorkspace.shared

        for screen in NSScreen.screens {
            try workspace.setDesktopImageURL(
                imageURL,
                for: screen,
                options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                    .allowClipping: true
                ]
            )
        }
    }

    /// Returns the current wallpaper URL for the main screen.
    func currentWallpaper() -> URL? {
        guard let screen = NSScreen.main else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)
    }
}
