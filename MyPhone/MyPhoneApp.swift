import SwiftUI

@main
struct MyPhoneApp: App {
    var body: some Scene {
        MenuBarExtra("MyPhone", systemImage: "iphone") {
            ContentView()
                .frame(width: 280)
        }
        .menuBarExtraStyle(.window)
    }
}
