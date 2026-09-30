import Foundation
import IOKit

struct TemperatureReading {
    let sensorName: String
    let celsius: Double
}

final class SMCReader {
    private let connection: io_connect_t

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var connection = io_connect_t()
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { return nil }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    func temperature() -> TemperatureReading? {
        for sensor in Self.temperatureSensors {
            guard let celsius = readTemperature(sensor.key), celsius > 0, celsius < 130 else {
                continue
            }
            return TemperatureReading(sensorName: sensor.name, celsius: celsius)
        }

        return nil
    }

    private func readTemperature(_ key: String) -> Double? {
        guard let value = readKey(key), value.dataSize >= 2 else { return nil }

        switch value.dataTypeString {
        case "sp78":
            let integer = Double(Int8(bitPattern: value.bytes.0))
            let fraction = Double(value.bytes.1) / 256.0
            return integer + fraction
        case "flt ":
            return withUnsafeBytes(of: value.bytes) { rawBuffer in
                guard rawBuffer.count >= 4 else { return nil }
                return Double(rawBuffer.load(as: Float.self))
            }
        case "fpe2":
            let raw = (UInt16(value.bytes.0) << 6) + (UInt16(value.bytes.1) >> 2)
            return Double(raw) / 4.0
        default:
            return nil
        }
    }

    private func readKey(_ key: String) -> SMCValue? {
        var input = SMCParamStruct()
        var output = SMCParamStruct()

        input.key = Self.fourCharCode(key)
        input.data8 = SMCCommand.readKeyInfo.rawValue

        guard call(input: &input, output: &output) == kIOReturnSuccess else { return nil }

        let dataSize = output.keyInfo.dataSize
        let dataType = output.keyInfo.dataType

        input = SMCParamStruct()
        output = SMCParamStruct()
        input.key = Self.fourCharCode(key)
        input.keyInfo.dataSize = dataSize
        input.keyInfo.dataType = dataType
        input.data8 = SMCCommand.readBytes.rawValue

        guard call(input: &input, output: &output) == kIOReturnSuccess else { return nil }

        return SMCValue(dataSize: dataSize, dataType: dataType, bytes: output.bytes)
    }

    private func call(input: inout SMCParamStruct, output: inout SMCParamStruct) -> kern_return_t {
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        return IOConnectCallStructMethod(
            connection,
            UInt32(kSMCHandleYPCEvent),
            &input,
            inputSize,
            &output,
            &outputSize
        )
    }

    private static func fourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + UInt32(scalar.value)
        }
        return result
    }

    private static let temperatureSensors: [(key: String, name: String)] = [
        ("TC0P", "CPU proximity"),
        ("TC0E", "CPU"),
        ("TC0F", "CPU"),
        ("TC1C", "CPU core 1"),
        ("TC2C", "CPU core 2"),
        ("Tp0P", "Processor proximity"),
        ("Tp1P", "Processor proximity"),
        ("TG0P", "GPU proximity")
    ]
}

private let kSMCHandleYPCEvent = 2

private enum SMCCommand: UInt8 {
    case readBytes = 5
    case readKeyInfo = 9
}

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCBytes {
    var data: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
               UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
               UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
               UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )

    var bytes: (UInt8, UInt8, UInt8, UInt8) {
        (data.0, data.1, data.2, data.3)
    }
}

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes = SMCBytes().data
}

private struct SMCValue {
    let dataSize: UInt32
    let dataType: UInt32
    let bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

    var dataTypeString: String {
        let scalars = [
            UInt8((dataType >> 24) & 0xff),
            UInt8((dataType >> 16) & 0xff),
            UInt8((dataType >> 8) & 0xff),
            UInt8(dataType & 0xff)
        ]
        return String(bytes: scalars, encoding: .ascii) ?? ""
    }
}
