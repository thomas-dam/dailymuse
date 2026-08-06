import SwiftUI
import UserNotifications

@main
struct DailyMuseApp: App {
    @StateObject private var appState = AppState()

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        MenuBarExtra("DailyMuse", systemImage: "paintpalette") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
