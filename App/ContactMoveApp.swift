import SwiftUI
import ContactsKit

@main
struct ContactMoveApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var permissions = ContactsPermissions()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .environmentObject(permissions)
        }
    }
}
