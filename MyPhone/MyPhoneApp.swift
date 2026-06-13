//
//  MyPhoneApp.swift
//  MyPhone
//
//  Created by Emre Yurtseven on 13.06.26.
//

import SwiftUI

@main
struct MyPhoneApp: App {
    @StateObject private var batteryService = BatteryService()

    var body: some Scene {
        MenuBarExtra(batteryService.menuBarTitle, systemImage: "iphone") {
            ContentView()
                .environmentObject(batteryService)
        }
        .menuBarExtraStyle(.window)
    }
}
