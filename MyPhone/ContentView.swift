import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var batteryService = BatteryService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(batteryService.deviceName)
                .font(.headline)

            Text("Battery: \(batteryService.batteryPercentage)")
            Text("Status: \(batteryService.chargingStatus)")
            if let binaryPath = batteryService.binaryPath {
                Text("Binary: \(binaryPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text("Last updated: \(batteryService.lastUpdated)")
                .foregroundStyle(.secondary)

            if let error = batteryService.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            Button("Refresh") {
                batteryService.refresh()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .onAppear {
            batteryService.startAutoRefresh(interval: 60)
        }
        .onDisappear {
            batteryService.stopAutoRefresh()
        }
    }
}
