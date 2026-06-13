//
//  ContentView.swift
//  MyPhone
//
//  Created by Emre Yurtseven on 13.06.26.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var batteryService: BatteryService

    private var batteryInt: Int? {
        let cleaned = batteryService.batteryPercentage.replacingOccurrences(of: "%", with: "")
        return Int(cleaned)
    }

    private var batteryColor: Color {
        guard let level = batteryInt else { return .secondary }
        if batteryService.chargingStatus == "Charging" { return .yellow }
        if level <= 20 { return .red }
        if level <= 50 { return .orange }
        return .green
    }

    private var batterySymbol: String {
        if batteryService.chargingStatus == "Charging" {
            return "battery.100.bolt"
        }

        guard let level = batteryInt else {
            return "battery.0"
        }

        switch level {
        case 76...100: return "battery.100"
        case 51...75:  return "battery.75"
        case 26...50:  return "battery.50"
        case 11...25:  return "battery.25"
        default:       return "battery.0"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Device name + connection badge ──────────────────────────
            HStack(spacing: 8) {
                Image(systemName: deviceSymbol)
                    .foregroundStyle(.primary)
                Text(batteryService.deviceName)
                    .font(.headline)
                Spacer()
                if let selected = selectedDevice {
                    Text(selected.connection.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(selected.connection == .usb ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                        .foregroundStyle(selected.connection == .usb ? .blue : .green)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            // ── Battery glyph + percentage ──────────────────────────────
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: batterySymbol)
                    .font(.system(size: 32))
                    .foregroundStyle(batteryColor)
                    .symbolEffect(.pulse, isActive: batteryService.chargingStatus == "Charging")

                VStack(alignment: .leading, spacing: 2) {
                    Text(batteryService.batteryPercentage)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(batteryColor)

                    Text(batteryService.chargingStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // ── Device picker ───────────────────────────────────────────
            if !batteryService.availableDevices.isEmpty {
                Menu {
                    ForEach(batteryService.availableDevices) { device in
                        Button(device.displayName) {
                            batteryService.selectedDeviceUDID = device.id
                        }
                        .disabled(device.id == batteryService.selectedDeviceUDID)
                    }
                } label: {
                    if let selected = batteryService.availableDevices.first(where: { $0.id == batteryService.selectedDeviceUDID }) {
                        Text(selected.displayName)
                    } else {
                        Text("Select Device")
                    }
                }
            } else {
                Text("No iPhone or iPad found")
                    .foregroundStyle(.secondary)
            }

            // ── Last updated ────────────────────────────────────────────
            Text("Updated: \(batteryService.lastUpdated)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // ── Error message ───────────────────────────────────────────
            if let error = batteryService.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Divider()

            // ── Buttons ─────────────────────────────────────────────────
            HStack(spacing: 8) {
                Button {
                    batteryService.refreshDevices()
                } label: {
                    Label("Devices", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }

                Button {
                    batteryService.refresh()
                } label: {
                    Label("Battery", systemImage: "bolt.fill")
                        .font(.caption)
                }

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .frame(width: 380)
        .onAppear {
            batteryService.start()
        }
        .onDisappear {
            batteryService.stop()
        }
    }

    private var selectedDevice: IOSDevice? {
        batteryService.availableDevices.first(where: { $0.id == batteryService.selectedDeviceUDID })
    }

    private var deviceSymbol: String {
        guard let device = selectedDevice else { return "iphone" }
        switch device.productFamily {
        case "iPad":      return "ipad"
        case "iPod":      return "ipodtouch"
        case "Apple TV":  return "appletv"
        default:          return "iphone"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(BatteryService())
}
