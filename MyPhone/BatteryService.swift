//
//  BatteryService.swift
//  MyPhone
//
//  Created by Emre Yurtseven on 13.06.26.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class BatteryService: ObservableObject {
    @Published var batteryPercentage: String = "--%"
    @Published var chargingStatus: String = "Disconnected"
    @Published var lastUpdated: String = "Never"
    @Published var deviceName: String = "iPhone"
    @Published var errorMessage: String?
    @Published var binaryPath: String?

    private var timer: Timer?

    func startAutoRefresh(interval: TimeInterval = 60) {
        stopAutoRefresh()
        refresh()

        let timer = Timer(timeInterval: interval, target: self, selector: #selector(handleTimer(_:)), userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func handleTimer(_ timer: Timer) {
        Task { @MainActor in
            self.refresh()
        }
    }

    func refresh() {
        Task.detached {
            let ideviceinfoPath = "/opt/homebrew/bin/ideviceinfo"

            let nameResult = self.runCommand(
                launchPath: ideviceinfoPath,
                arguments: ["-n", "-k", "DeviceName"]
            )

            let batteryResult = self.runCommand(
                launchPath: ideviceinfoPath,
                arguments: ["-n", "-q", "com.apple.mobile.battery", "-k", "BatteryCurrentCapacity"]
            )

            let chargingResult = self.runCommand(
                launchPath: ideviceinfoPath,
                arguments: ["-n", "-q", "com.apple.mobile.battery", "-k", "BatteryIsCharging"]
            )

            await MainActor.run {
                if let name = nameResult.output?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !name.isEmpty {
                    self.deviceName = name
                } else {
                    self.deviceName = "iPhone"
                }

                if let battery = batteryResult.output?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !battery.isEmpty {
                    self.batteryPercentage = "\(battery)%"
                    self.errorMessage = nil
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
                let batteryError = batteryResult.errorOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let chargingError = chargingResult.errorOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                let combinedError = [nameError, batteryError, chargingError]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

                if batteryResult.exitCode != 0 || nameResult.exitCode != 0 || chargingResult.exitCode != 0 {
                    self.errorMessage = combinedError.isEmpty
                        ? "Could not talk to the iPhone."
                        : combinedError
                    self.chargingStatus = "Disconnected"
                } else {
                    self.errorMessage = nil
                }

                self.lastUpdated = Date.now.formatted(date: .omitted, time: .standard)
            }
        }
    }

    nonisolated private func findIdeviceinfoBinary() -> String? {
        let fileManager = FileManager.default

        let commonPaths = [
            "/opt/homebrew/bin/ideviceinfo",
            "/opt/homebrew/Cellar/libimobiledevice/1.4.0/bin/ideviceinfo",
            "/usr/local/bin/ideviceinfo"
        ]

        for path in commonPaths {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
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

struct CommandResult {
    let output: String?
    let errorOutput: String?
    let exitCode: Int32
}
