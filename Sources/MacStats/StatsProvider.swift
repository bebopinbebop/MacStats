import Foundation
import MachO

struct SystemSnapshot {
    let cpu: CPUStats
    let memory: MemoryStats
    let temperature: TemperatureStats
    let thermalState: ProcessInfo.ThermalState
    let updated: Date

    var menuBarTitle: String {
        let temperatureText = temperature.shortText
        if temperatureText.isEmpty {
            return "CPU: \(cpu.shortText)  RAM: \(memory.shortText)"
        }
        return "CPU: \(cpu.shortText)  RAM: \(memory.shortText)  Temp: \(temperatureText)"
    }

    var tooltip: String {
        [
            "CPU: \(cpu.formattedLong)",
            "Memory: \(memory.formattedLong)",
            "Temperature: \(temperature.formattedLong)",
            "Thermal State: \(thermalState.displayName)",
        ].joined(separator: "\n")
    }

    var clipboardText: String {
        [
            "CPU: \(cpu.formattedLong)",
            "Memory: \(memory.formattedLong)",
            "Temperature: \(temperature.formattedLong)",
            "Thermal State: \(thermalState.displayName)",
            "Updated: \(updated.formatted(date: .numeric, time: .standard))",
        ].joined(separator: "\n")
    }
}

struct CPUStats {
    let usagePercent: Double
    let coreCount: Int

    var shortText: String {
        "\(usagePercent.roundedInt)%"
    }

    var formattedLong: String {
        "\(usagePercent.roundedOneDecimal)% across \(coreCount) logical cores"
    }
}

struct MemoryStats {
    let usedBytes: UInt64
    let cachedBytes: UInt64
    let totalBytes: UInt64

    var usagePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }

    var shortText: String {
        "\(usagePercent.roundedInt)%"
    }

    var formattedLong: String {
        "\(Self.formatBytes(usedBytes)) / \(Self.formatBytes(totalBytes)) (\(usagePercent.roundedInt)%), cached \(Self.formatBytes(cachedBytes))"
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct TemperatureStats {
    let celsius: Double?
    let sensorName: String?
    let source: String?
    let unavailableReason: String?

    var shortText: String {
        guard let celsius else { return "" }
        return "\(celsius.roundedInt)C"
    }

    var formattedLong: String {
        guard let celsius else {
            if let unavailableReason {
                return "Unavailable: \(unavailableReason)"
            }
            return "Unavailable"
        }

        let sourceText = source.map { ", \($0)" } ?? ""
        if let sensorName {
            return "\(celsius.roundedOneDecimal)C (\(sensorName)\(sourceText))"
        }
        return "\(celsius.roundedOneDecimal)C\(sourceText)"
    }
}

final class StatsProvider {
    private var previousCPULoad: host_cpu_load_info_data_t?
    private let smc = SMCReader()
    private let powermetrics = PowermetricsReader()
    private var cachedTemperature = TemperatureStats(
        celsius: nil, sensorName: nil, source: nil, unavailableReason: "warming up")
    private var lastTemperatureRefresh = Date.distantPast
    private var isRefreshingTemperature = false
    private let temperatureLock = NSLock()
    private let temperatureRefreshInterval: TimeInterval = 10

    func snapshot() -> SystemSnapshot {
        SystemSnapshot(
            cpu: cpuStats(),
            memory: memoryStats(),
            temperature: currentTemperatureStats(),
            thermalState: ProcessInfo.processInfo.thermalState,
            updated: Date()
        )
    }

    private func cpuStats() -> CPUStats {
        var size = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var load = host_cpu_load_info_data_t()

        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }

        guard result == KERN_SUCCESS else {
            return CPUStats(usagePercent: 0, coreCount: ProcessInfo.processInfo.processorCount)
        }

        defer { previousCPULoad = load }
        guard let previousCPULoad else {
            return CPUStats(usagePercent: 0, coreCount: ProcessInfo.processInfo.processorCount)
        }

        let user = Double(load.cpu_ticks.0 - previousCPULoad.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1 - previousCPULoad.cpu_ticks.1)
        let idle = Double(load.cpu_ticks.2 - previousCPULoad.cpu_ticks.2)
        let nice = Double(load.cpu_ticks.3 - previousCPULoad.cpu_ticks.3)
        let total = user + system + idle + nice
        let usage = total > 0 ? (total - idle) / total * 100 : 0

        return CPUStats(
            usagePercent: max(0, min(100, usage)), coreCount: ProcessInfo.processInfo.processorCount
        )
    }

    private func memoryStats() -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory

        guard result == KERN_SUCCESS else {
            return MemoryStats(usedBytes: 0, cachedBytes: 0, totalBytes: total)
        }

        let usedPages = UInt64(
            stats.internal_page_count + stats.wire_count + stats.compressor_page_count)
        let cachedPages = UInt64(stats.external_page_count + stats.purgeable_count)

        return MemoryStats(
            usedBytes: usedPages * pageSize,
            cachedBytes: cachedPages * pageSize,
            totalBytes: total
        )
    }

    private func currentTemperatureStats() -> TemperatureStats {
        let now = Date()
        temperatureLock.lock()
        let cached = cachedTemperature
        let shouldRefresh =
            !isRefreshingTemperature
            && now.timeIntervalSince(lastTemperatureRefresh) >= temperatureRefreshInterval
        if shouldRefresh {
            isRefreshingTemperature = true
            lastTemperatureRefresh = now
        }
        temperatureLock.unlock()

        if shouldRefresh {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.refreshTemperature()
            }
        }

        return cached
    }

    private func refreshTemperature() {
        let refreshedTemperature: TemperatureStats
        let powermetricsResult = powermetrics.temperature()
        if case .success(let reading) = powermetricsResult {
            refreshedTemperature = TemperatureStats(
                celsius: reading.celsius,
                sensorName: reading.sensorName,
                source: "powermetrics",
                unavailableReason: nil
            )
        } else if let reading = smc?.temperature() {
            refreshedTemperature = TemperatureStats(
                celsius: reading.celsius,
                sensorName: reading.sensorName,
                source: "AppleSMC",
                unavailableReason: nil
            )
        } else {
            let message: String
            if case .failure(let error) = powermetricsResult {
                message = error.displayMessage
            } else {
                message = "no SMC temperature sensor returned data"
            }

            refreshedTemperature = TemperatureStats(
                celsius: nil,
                sensorName: nil,
                source: nil,
                unavailableReason: message
            )
        }

        temperatureLock.lock()
        cachedTemperature = refreshedTemperature
        isRefreshingTemperature = false
        temperatureLock.unlock()
    }
}

extension ProcessInfo.ThermalState {
    var displayName: String {
        switch self {
        case .nominal:
            return "Nominal"
        case .fair:
            return "Fair"
        case .serious:
            return "Serious"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }
}

extension Double {
    fileprivate var roundedInt: String {
        String(format: "%.0f", self)
    }

    fileprivate var roundedOneDecimal: String {
        String(format: "%.1f", self)
    }
}
