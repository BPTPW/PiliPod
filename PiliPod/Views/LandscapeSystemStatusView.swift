//
//  LandscapeSystemStatusView.swift
//  PiliPod
//
//  Created by Codex on 2026/6/21.
//

import SwiftUI
import Combine
#if canImport(Network)
import Network
#endif
#if canImport(UIKit)
import UIKit
#endif

private struct BatteryStatus: Equatable {
    let level: Int
    let isCharging: Bool

    var iconName: String {
        if isCharging {
            return "battery.100percent.bolt"
        }

        switch level {
        case 90...100:
            return "battery.100percent"
        case 66...89:
            return "battery.75percent"
        case 36...65:
            return "battery.50percent"
        case 11...35:
            return "battery.25percent"
        default:
            return "battery.0percent"
        }
    }

    var text: String {
        "\(level)%"
    }
}

private enum NetworkStatus: Equatable {
    case wifi
    case cellular
    case other

    var iconName: String? {
        switch self {
        case .wifi:
            return "wifi"
        case .cellular:
            return "cellularbars"
        case .other:
            return nil
        }
    }
}

struct LandscapeSystemStatusView: View {
    @State private var currentDate = Date()
    @State private var batteryStatus = BatteryStatus(level: 100, isCharging: false)
    @State private var networkStatus: NetworkStatus = .other

#if canImport(Network)
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "pili.landscape.network.monitor")
#endif

    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            
            Text(currentTimeText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            
            Spacer()

            if let networkIconName = networkStatus.iconName {
                Image(systemName: networkIconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 4) {
                batteryIcon

                Text(batteryStatus.text)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity,maxHeight: .infinity, alignment: .top)
        .task {
            updateBatteryStatus()
            startNetworkMonitoring()
        }
        .onDisappear {
            stopNetworkMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            updateBatteryStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            updateBatteryStatus()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            currentDate = date
        }
    }

    private var currentTimeText: String {
        if Self.uses12HourClock {
            let period = Self.periodFormatter.string(from: currentDate)
            let time = Self.twelveHourTimeFormatter.string(from: currentDate)
            return "\(period) \(time)"
        }

        return Self.twentyFourHourTimeFormatter.string(from: currentDate)
    }

    @ViewBuilder
    private var batteryIcon: some View {
        let image = Image(systemName: batteryStatus.iconName)
            .font(.system(size: 12, weight: .medium))

        if batteryStatus.isCharging {
            image
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .white, .green)
        } else {
            image
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
        }
    }

    private static let uses12HourClock: Bool = {
        let hourFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "HH"
        return hourFormat.contains("a")
    }()

    private static let periodFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("B")
        return formatter
    }()

    private static let twelveHourTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "hh:mm"
        return formatter
    }()

    private static let twentyFourHourTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func updateBatteryStatus() {
#if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true

        let level = UIDevice.current.batteryLevel
        let resolvedLevel: Int
        if level >= 0 {
            resolvedLevel = Int((level * 100).rounded())
        } else {
            resolvedLevel = 100
        }

        let batteryState = UIDevice.current.batteryState
        batteryStatus = BatteryStatus(
            level: min(max(resolvedLevel, 0), 100),
            isCharging: batteryState == .charging || batteryState == .full
        )
#endif
    }

    private func startNetworkMonitoring() {
#if canImport(Network)
        networkMonitor.pathUpdateHandler = { path in
            let nextStatus: NetworkStatus
            if path.usesInterfaceType(.wifi) {
                nextStatus = .wifi
            } else if path.usesInterfaceType(.cellular) {
                nextStatus = .cellular
            } else {
                nextStatus = .other
            }

            Task { @MainActor in
                networkStatus = nextStatus
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
#endif
    }

    private func stopNetworkMonitoring() {
#if canImport(Network)
        networkMonitor.cancel()
#endif
    }
}
