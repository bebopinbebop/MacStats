import Foundation

final class PowermetricsReader {
    private let executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")

    func temperature() -> Result<TemperatureReading, PowermetricsError> {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--samplers", "smc", "-i", "1000", "-n", "1"]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            return .failure(.launchFailed(error.localizedDescription))
        }

        let deadline = Date().addingTimeInterval(15)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            return .failure(.timedOut)
        }

        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            return .failure(.exited(process.terminationStatus, errorText))
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            return .failure(.unreadableOutput)
        }

        guard let reading = Self.parseTemperature(from: text) else {
            return .failure(.temperatureNotFound)
        }

        return .success(reading)
    }

    static func parseTemperature(from text: String) -> TemperatureReading? {
        let readings = text
            .split(whereSeparator: \.isNewline)
            .compactMap { parseTemperatureLine(String($0)) }

        return readings.first { $0.sensorName.localizedCaseInsensitiveContains("CPU") }
            ?? readings.first { $0.sensorName.localizedCaseInsensitiveContains("die") }
            ?? readings.first
    }

    private static func parseTemperatureLine(_ line: String) -> TemperatureReading? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.localizedCaseInsensitiveContains("temperature"),
              trimmed.localizedCaseInsensitiveContains("C") else {
            return nil
        }

        let pattern = #"^(.+?):\s*([0-9]+(?:\.[0-9]+)?)\s*C\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              match.numberOfRanges >= 3,
              let nameRange = Range(match.range(at: 1), in: trimmed),
              let valueRange = Range(match.range(at: 2), in: trimmed),
              let celsius = Double(trimmed[valueRange]),
              celsius > 0,
              celsius < 130 else {
            return nil
        }

        return TemperatureReading(
            sensorName: String(trimmed[nameRange]),
            celsius: celsius
        )
    }
}

enum PowermetricsError: Error {
    case launchFailed(String)
    case timedOut
    case exited(Int32, String?)
    case unreadableOutput
    case temperatureNotFound

    var displayMessage: String {
        switch self {
        case .launchFailed(let message):
            return "powermetrics launch failed: \(message)"
        case .timedOut:
            return "powermetrics timed out"
        case .exited(_, let message):
            if let message, !message.isEmpty {
                return message
            }
            return "powermetrics exited without data"
        case .unreadableOutput:
            return "powermetrics output was unreadable"
        case .temperatureNotFound:
            return "powermetrics returned no temperature line"
        }
    }
}
