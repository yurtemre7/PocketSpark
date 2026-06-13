//
//  BatteryService.swift
//  MyPhone
//
//  Created by Emre Yurtseven on 13.06.26.
//

import Foundation
import SwiftUI
import Combine

enum ConnectionType: String, Codable, Hashable {
    case usb = "USB"
    case network = "Wi‑Fi"
}

struct IOSDevice: Identifiable, Hashable {
    let id: String            // UDID
    let name: String
    let productType: String
    let productFamily: String
    let connection: ConnectionType

    var displayName: String {
        "\(productFamily) — \(name) (\(connection.rawValue))"
    }

    var shortMenuTitle: String {
        if name.isEmpty {
            return productFamily
        }
        return "\(productFamily): \(name)"
    }
}

struct CommandResult {
    let output: String?
    let errorOutput: String?
    let exitCode: Int32
}

@MainActor
final class BatteryService: ObservableObject {
    @Published var batteryPercentage: String = "--%"
    @Published var chargingStatus: String = "Disconnected"
    @Published var lastUpdated: String = "Never"
    @Published var deviceName: String = "No Device"
    @Published var errorMessage: String?
    @Published var availableDevices: [IOSDevice] = []
    @Published var menuBarTitle: String = "MyPhone"

    @Published var selectedDeviceUDID: String {
        didSet {
            UserDefaults.standard.set(selectedDeviceUDID, forKey: Self.selectedDeviceKey)
            refresh()
        }
    }

    private var batteryTimer: Timer?
    private var deviceRefreshTimer: Timer?

    private static let selectedDeviceKey = "SelectedDeviceUDID"

    private let ideviceinfoPath = "/opt/homebrew/bin/ideviceinfo"
    private let ideviceIDPath = "/opt/homebrew/bin/idevice_id"

    init() {
        self.selectedDeviceUDID = UserDefaults.standard.string(forKey: Self.selectedDeviceKey) ?? ""
    }

    func start() {
        stop()
        refreshDevices()
        refresh()

        let batteryTimer = Timer(timeInterval: 60, target: self, selector: #selector(handleBatteryTimer(_:)), userInfo: nil, repeats: true)
        self.batteryTimer = batteryTimer
        RunLoop.main.add(batteryTimer, forMode: .common)

        let deviceRefreshTimer = Timer(timeInterval: 180, target: self, selector: #selector(handleDeviceRefreshTimer(_:)), userInfo: nil, repeats: true)
        self.deviceRefreshTimer = deviceRefreshTimer
        RunLoop.main.add(deviceRefreshTimer, forMode: .common)
    }

    func stop() {
        batteryTimer?.invalidate()
        batteryTimer = nil

        deviceRefreshTimer?.invalidate()
        deviceRefreshTimer = nil
    }

    @objc private func handleBatteryTimer(_ timer: Timer) {
        Task { @MainActor in
            self.refresh()
        }
    }

    @objc private func handleDeviceRefreshTimer(_ timer: Timer) {
        Task { @MainActor in
            self.refreshDevices()
        }
    }

    func refreshDevices() {
        Task.detached {
            guard FileManager.default.isExecutableFile(atPath: self.ideviceIDPath),
                  FileManager.default.isExecutableFile(atPath: self.ideviceinfoPath) else {
                await MainActor.run {
                    self.availableDevices = []
                    self.errorMessage = "Required binaries not found in /opt/homebrew/bin"
                    self.menuBarTitle = "MyPhone"
                }
                return
            }

            let usbUDIDs = self.fetchUDIDs(arguments: ["-l"])
            let networkUDIDs = self.fetchUDIDs(arguments: ["-n"])

            var devicesByUDID: [String: IOSDevice] = [:]

            for udid in usbUDIDs {
                if let device = self.resolveDevice(udid: udid, connection: .usb) {
                    devicesByUDID[udid] = device
                }
            }

            for udid in networkUDIDs {
                if devicesByUDID[udid] == nil,
                   let device = self.resolveDevice(udid: udid, connection: .network) {
                    devicesByUDID[udid] = device
                }
            }

            let devices = Array(devicesByUDID.values)
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            await MainActor.run {
                self.availableDevices = devices

                if devices.isEmpty {
                    self.selectedDeviceUDID = ""
                    self.deviceName = "No Device"
                    self.menuBarTitle = "MyPhone"
                    return
                }

                if self.selectedDeviceUDID.isEmpty || !devices.contains(where: { $0.id == self.selectedDeviceUDID }) {
                    self.selectedDeviceUDID = devices.first!.id
                } else if let current = devices.first(where: { $0.id == self.selectedDeviceUDID }) {
                    self.deviceName = current.name
                    self.updateMenuBarTitle(using: current)
                }
            }
        }
    }

    func refresh() {
        Task.detached {
            guard FileManager.default.isExecutableFile(atPath: self.ideviceinfoPath) else {
                await MainActor.run {
                    self.batteryPercentage = "--%"
                    self.chargingStatus = "Disconnected"
                    self.lastUpdated = Date.now.formatted(date: .omitted, time: .standard)
                    self.errorMessage = "ideviceinfo not found at \(self.ideviceinfoPath)"
                    self.menuBarTitle = "MyPhone"
                }
                return
            }

            let selectedUDID = await MainActor.run { self.selectedDeviceUDID }
            let devices = await MainActor.run { self.availableDevices }

            guard !selectedUDID.isEmpty else {
                await MainActor.run {
                    self.batteryPercentage = "--%"
                    self.chargingStatus = "Disconnected"
                    self.lastUpdated = Date.now.formatted(date: .omitted, time: .standard)
                    self.errorMessage = "No iPhone selected."
                    self.menuBarTitle = "MyPhone"
                }
                return
            }

            let selectedDevice = devices.first(where: { $0.id == selectedUDID })

            let connection: ConnectionType = selectedDevice?.connection ?? .network
            let transportFlag = (connection == .usb) ? [] : ["-n"]

            let baseArgs = transportFlag + ["-u", selectedUDID]

            let nameResult = self.runCommand(
                launchPath: self.ideviceinfoPath,
                arguments: baseArgs + ["-k", "DeviceName"]
            )

            let productTypeResult = self.runCommand(
                launchPath: self.ideviceinfoPath,
                arguments: baseArgs + ["-k", "ProductType"]
            )

            let batteryResult = self.runCommand(
                launchPath: self.ideviceinfoPath,
                arguments: baseArgs + ["-q", "com.apple.mobile.battery", "-k", "BatteryCurrentCapacity"]
            )

            let chargingResult = self.runCommand(
                launchPath: self.ideviceinfoPath,
                arguments: baseArgs + ["-q", "com.apple.mobile.battery", "-k", "BatteryIsCharging"]
            )

            await MainActor.run {
                let resolvedName = nameResult.output?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedProductType = productTypeResult.output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let resolvedFamily = Self.productFamily(from: resolvedProductType)

                self.deviceName = (resolvedName?.isEmpty == false) ? resolvedName! : "iPhone"

                if let battery = batteryResult.output?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !battery.isEmpty {
                    self.batteryPercentage = "\(battery)%"
                } else {
                    self.batteryPercentage = "--%"
                }

                if let charging = chargingResult.output?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                   !charging.isEmpty {
                    self.chargingStatus = (charging == "true") ? "Charging" : "Not charging"
                } else {
                    self.chargingStatus = "Unknown"
                }

                let nameError = nameResult.errorOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let typeError = productTypeResult.errorOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let batteryError = batteryResult.errorOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let chargingError = chargingResult.errorOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                let combinedError = [nameError, typeError, batteryError, chargingError]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

                if batteryResult.exitCode != 0 || nameResult.exitCode != 0 {
                    self.errorMessage = combinedError.isEmpty ? "Could not talk to the selected device." : combinedError
                    self.chargingStatus = "Disconnected"
                } else {
                    self.errorMessage = nil
                }

                let family = resolvedFamily.isEmpty ? "iPhone" : resolvedFamily
                let conn = connection.rawValue
                self.menuBarTitle = "\(family) \(self.batteryPercentage)"

                if let index = self.availableDevices.firstIndex(where: { $0.id == selectedUDID }) {
                    let existing = self.availableDevices[index]
                    self.availableDevices[index] = IOSDevice(
                        id: existing.id,
                        name: (resolvedName?.isEmpty == false) ? resolvedName! : existing.name,
                        productType: resolvedProductType.isEmpty ? existing.productType : resolvedProductType,
                        productFamily: family,
                        connection: existing.connection
                    )
                }

                self.lastUpdated = Date.now.formatted(date: .omitted, time: .standard)
            }
        }
    }

    func manualRefreshAll() {
        refreshDevices()
        refresh()
    }

    private func updateMenuBarTitle(using device: IOSDevice) {
        if batteryPercentage != "--%" {
            menuBarTitle = "\(device.productFamily) \(batteryPercentage)"
        } else {
            menuBarTitle = device.productFamily
        }
    }

    nonisolated private func fetchUDIDs(arguments: [String]) -> [String] {
        let result = runCommand(
            launchPath: ideviceIDPath,
            arguments: arguments
        )

        return (result.output ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated private func resolveDevice(udid: String, connection: ConnectionType) -> IOSDevice? {
        let transportFlag = (connection == .usb) ? [] : ["-n"]
        let baseArgs = transportFlag + ["-u", udid]

        let nameResult = runCommand(
            launchPath: ideviceinfoPath,
            arguments: baseArgs + ["-k", "DeviceName"]
        )

        let productTypeResult = runCommand(
            launchPath: ideviceinfoPath,
            arguments: baseArgs + ["-k", "ProductType"]
        )

        guard nameResult.exitCode == 0 || productTypeResult.exitCode == 0 else {
            return nil
        }

        let name = nameResult.output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown Device"
        let productType = productTypeResult.output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let family = Self.productFamily(from: productType)

        return IOSDevice(
            id: udid,
            name: name.isEmpty ? "Unknown Device" : name,
            productType: productType,
            productFamily: family,
            connection: connection
        )
    }

    nonisolated private static func productFamily(from productType: String) -> String {
        if productType.hasPrefix("iPhone") { return "iPhone" }
        if productType.hasPrefix("iPad") { return "iPad" }
        if productType.hasPrefix("iPod") { return "iPod" }
        if productType.hasPrefix("AppleTV") { return "Apple TV" }
        return "iOS Device"
    }

    nonisolated private func runCommand(launchPath: String, arguments: [String]) -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8)
            let errorOutput = String(data: errorData, encoding: .utf8)

            return CommandResult(
                output: output,
                errorOutput: errorOutput,
                exitCode: process.terminationStatus
            )
        } catch {
            return CommandResult(
                output: nil,
                errorOutput: error.localizedDescription,
                exitCode: -1
            )
        }
    }
}
