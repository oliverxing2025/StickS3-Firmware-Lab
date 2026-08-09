import Foundation

public struct StickS3VirtualBoardFrame: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let sequence: UInt32
    public let rgb565: Data

    public init(width: Int, height: Int, sequence: UInt32, rgb565: Data) {
        self.width = width
        self.height = height
        self.sequence = sequence
        self.rgb565 = rgb565
    }
}

public struct StickS3VirtualBoardCapabilities: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let display = Self(rawValue: 1 << 0)
    public static let buttons = Self(rawValue: 1 << 1)
    public static let bmi270 = Self(rawValue: 1 << 2)
    public static let power = Self(rawValue: 1 << 3)
    public static let audio = Self(rawValue: 1 << 4)
    public static let hostNetwork = Self(rawValue: 1 << 5)
}

public struct StickS3HostNetworkRequest: Equatable, Sendable {
    public let requestID: UInt32
    public let method: UInt8
    public let timeoutMilliseconds: UInt32
    public let url: String
    public let headers: String
    public let body: Data

    public init(requestID: UInt32, method: UInt8, timeoutMilliseconds: UInt32,
                url: String, headers: String, body: Data) {
        self.requestID = requestID
        self.method = method
        self.timeoutMilliseconds = timeoutMilliseconds
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct StickS3VirtualBoardReport: Equatable, Sendable {
    public let capabilities: StickS3VirtualBoardCapabilities
    public let logicalX: StickS3AxisBinding
    public let logicalY: StickS3AxisBinding
    public let logicalZ: StickS3AxisBinding
    public let frontButton: StickS3ButtonHardware
    public let sideButton: StickS3ButtonHardware
    public let displayRotation: StickS3DisplayRotation
    public let compatibility: StickS3HardwareCompatibility
}

public enum StickS3VirtualBoardEvent: Equatable, Sendable {
    case ready(StickS3VirtualBoardReport)
    case frame(StickS3VirtualBoardFrame)
    case audio(UInt8)
    case hostNetworkRequest(StickS3HostNetworkRequest)
    case log(Data)
}

public struct StickS3VirtualBoardStreamParser: Sendable {
    private static let magic = Data([0x53, 0x33, 0x56, 0x44]) // S3VD
    private static let headerSize = 10
    private static let maximumPayloadSize = 1_048_576
    private var buffer = Data()
    private var framePixels = Data()
    private var frameWidth = 0
    private var frameHeight = 0

    public init() {}

    public mutating func append(_ data: Data) -> [StickS3VirtualBoardEvent] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)
        var events: [StickS3VirtualBoardEvent] = []
        while !buffer.isEmpty {
            guard let magicRange = buffer.range(of: Self.magic) else {
                let retained = min(buffer.count, Self.magic.count - 1)
                let logCount = buffer.count - retained
                if logCount > 0 {
                    events.append(.log(buffer.prefix(logCount)))
                    buffer.removeFirst(logCount)
                }
                break
            }
            if magicRange.lowerBound > buffer.startIndex {
                let log = buffer[..<magicRange.lowerBound]
                events.append(.log(Data(log)))
                buffer.removeSubrange(..<magicRange.lowerBound)
            }
            guard buffer.count >= Self.headerSize else { break }
            let version = readByte(buffer, at: 4)
            let type = readByte(buffer, at: 5)
            let length = Int(readUInt32LE(buffer, at: 6))
            guard version == 1, length <= Self.maximumPayloadSize else {
                events.append(.log(buffer.prefix(1)))
                buffer.removeFirst(1)
                continue
            }
            guard buffer.count >= Self.headerSize + length else { break }
            let payloadStart = buffer.index(buffer.startIndex, offsetBy: Self.headerSize)
            let payloadEnd = buffer.index(payloadStart, offsetBy: length)
            let payload = Data(buffer[payloadStart..<payloadEnd])
            buffer.removeFirst(Self.headerSize + length)
            switch type {
            case 0x01 where payload.count >= 10:
                let status = StickS3HardwareCompatibility(wireValue: readByte(payload, at: 9))
                if let x = StickS3AxisBinding(wireValue: Int8(bitPattern: readByte(payload, at: 1))),
                   let y = StickS3AxisBinding(wireValue: Int8(bitPattern: readByte(payload, at: 2))),
                   let z = StickS3AxisBinding(wireValue: Int8(bitPattern: readByte(payload, at: 3))),
                   let rotation = StickS3DisplayRotation(rawValue: Int(readByte(payload, at: 8)) * 90) {
                    events.append(.ready(.init(
                        capabilities: .init(rawValue: readByte(payload, at: 0)),
                        logicalX: x, logicalY: y, logicalZ: z,
                        frontButton: .init(gpio: Int(readByte(payload, at: 4)), activeLow: readByte(payload, at: 6) != 0),
                        sideButton: .init(gpio: Int(readByte(payload, at: 5)), activeLow: readByte(payload, at: 7) != 0),
                        displayRotation: rotation, compatibility: status)))
                }
            case 0x01 where payload.count >= 1:
                events.append(.ready(.init(
                    capabilities: .init(rawValue: readByte(payload, at: 0)),
                    logicalX: .init(.x), logicalY: .init(.y), logicalZ: .init(.z),
                    frontButton: .init(gpio: 11), sideButton: .init(gpio: 12),
                    displayRotation: .degrees0, compatibility: .needsCalibration)))
            case 0x02 where payload.count >= 8:
                let width = Int(readUInt16LE(payload, at: 0))
                let height = Int(readUInt16LE(payload, at: 2))
                let sequence = readUInt32LE(payload, at: 4)
                let pixels = payload.dropFirst(8)
                if width > 0, height > 0, width * height * 2 == pixels.count {
                    frameWidth = width
                    frameHeight = height
                    framePixels = Data(pixels)
                    events.append(.frame(StickS3VirtualBoardFrame(
                        width: width, height: height, sequence: sequence, rgb565: framePixels)))
                }
            case 0x04 where payload.count >= 12 && (payload.count - 8).isMultiple(of: 4):
                let width = Int(readUInt16LE(payload, at: 0))
                let height = Int(readUInt16LE(payload, at: 2))
                let sequence = readUInt32LE(payload, at: 4)
                let expectedBytes = width * height * 2
                var pixels = Data()
                pixels.reserveCapacity(expectedBytes)
                var offset = 8
                while offset + 3 < payload.count && pixels.count <= expectedBytes {
                    let count = Int(readUInt16LE(payload, at: offset))
                    guard count > 0 else { pixels.removeAll(); break }
                    let low = readByte(payload, at: offset + 2)
                    let high = readByte(payload, at: offset + 3)
                    guard pixels.count + count * 2 <= expectedBytes else {
                        pixels.removeAll(); break
                    }
                    for _ in 0..<count { pixels.append(low); pixels.append(high) }
                    offset += 4
                }
                if width > 0, height > 0, pixels.count == expectedBytes {
                    frameWidth = width
                    frameHeight = height
                    framePixels = pixels
                    events.append(.frame(StickS3VirtualBoardFrame(
                        width: width, height: height, sequence: sequence, rgb565: framePixels)))
                }
            case 0x05 where payload.count >= 8:
                let width = Int(readUInt16LE(payload, at: 0))
                let height = Int(readUInt16LE(payload, at: 2))
                let sequence = readUInt32LE(payload, at: 4)
                let expectedBytes = width * height * 2
                guard width == frameWidth, height == frameHeight,
                      framePixels.count == expectedBytes else { break }
                var offset = 8
                var valid = true
                while offset < payload.count {
                    guard offset + 4 <= payload.count else { valid = false; break }
                    let pixelOffset = Int(readUInt16LE(payload, at: offset))
                    let pixelCount = Int(readUInt16LE(payload, at: offset + 2))
                    let byteCount = pixelCount * 2
                    let sourceStart = offset + 4
                    guard pixelCount > 0, pixelOffset + pixelCount <= width * height,
                          sourceStart + byteCount <= payload.count else {
                        valid = false
                        break
                    }
                    framePixels.replaceSubrange(
                        (pixelOffset * 2)..<((pixelOffset + pixelCount) * 2),
                        with: payload[sourceStart..<(sourceStart + byteCount)])
                    offset = sourceStart + byteCount
                }
                if valid, offset == payload.count {
                    events.append(.frame(StickS3VirtualBoardFrame(
                        width: width, height: height, sequence: sequence, rgb565: framePixels)))
                }
            case 0x03 where payload.count == 1:
                events.append(.audio(readByte(payload, at: 0)))
            case 0x20 where payload.count >= 17:
                let requestID = readUInt32LE(payload, at: 0)
                let method = readByte(payload, at: 4)
                let timeout = readUInt32LE(payload, at: 5)
                let urlLength = Int(readUInt16LE(payload, at: 9))
                let headerLength = Int(readUInt16LE(payload, at: 11))
                let bodyLength = Int(readUInt32LE(payload, at: 13))
                let expected = 17 + urlLength + headerLength + bodyLength
                guard expected == payload.count else { break }
                let urlStart = 17
                let headerStart = urlStart + urlLength
                let bodyStart = headerStart + headerLength
                guard let url = String(data: payload[urlStart..<headerStart], encoding: .utf8),
                      let headers = String(data: payload[headerStart..<bodyStart], encoding: .utf8)
                else { break }
                events.append(.hostNetworkRequest(.init(
                    requestID: requestID, method: method,
                    timeoutMilliseconds: timeout, url: url, headers: headers,
                    body: Data(payload[bodyStart..<payload.count]))))
            default:
                break
            }
        }
        return events
    }

    private func readByte(_ data: Data, at offset: Int) -> UInt8 {
        data[data.index(data.startIndex, offsetBy: offset)]
    }

    private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(readByte(data, at: offset)) | (UInt16(readByte(data, at: offset + 1)) << 8)
    }

    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(readByte(data, at: offset))
            | (UInt32(readByte(data, at: offset + 1)) << 8)
            | (UInt32(readByte(data, at: offset + 2)) << 16)
            | (UInt32(readByte(data, at: offset + 3)) << 24)
    }
}

public enum StickS3VirtualBoardButton: UInt8, Sendable {
    case front = 0
    case side = 1
}

public struct StickS3VirtualBoardMotionVector: Equatable, Sendable {
    public let x: Float
    public let y: Float
    public let z: Float

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct StickS3VirtualBoardMotionMap: Sendable {
    public init() {}

    public func sensorVector(report: StickS3VirtualBoardReport?, logicalX: Float,
                             logicalY: Float, logicalZ: Float)
        -> StickS3VirtualBoardMotionVector {
        guard let report else {
            return StickS3VirtualBoardMotionVector(
                x: logicalX, y: logicalY, z: logicalZ)
        }
        let profile = StickS3VirtualHardwareProfile(
            sourceFingerprint: "", compatibility: report.compatibility,
            capabilities: report.capabilities, logicalX: report.logicalX,
            logicalY: report.logicalY, logicalZ: report.logicalZ,
            frontButton: report.frontButton, sideButton: report.sideButton,
            displayRotation: report.displayRotation)
        return profile.sensorVector(logicalX: logicalX, logicalY: logicalY, logicalZ: logicalZ)
    }
}

private extension StickS3HardwareCompatibility {
    init(wireValue: UInt8) {
        self = switch wireValue {
        case 0: .verified
        case 1: .autoDetected
        case 2: .needsCalibration
        default: .unsupported
        }
    }
}

public struct StickS3VirtualBoardPacketEncoder: Sendable {
    public init() {}

    public func button(_ button: StickS3VirtualBoardButton, clicks: Int) -> Data {
        packet(type: 0x11, payload: Data([button.rawValue, UInt8(clamping: clicks)]))
    }

    public func motion(x: Float, y: Float, z: Float) -> Data {
        var payload = Data()
        for value in [x, y, z] {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { payload.append(contentsOf: $0) }
        }
        return packet(type: 0x12, payload: payload)
    }

    public func deviceState(batteryPercent: Int, charging: Bool,
                            soundEnabled: Bool, framesPerSecond: Int) -> Data {
        packet(type: 0x13, payload: Data([
            UInt8(clamping: batteryPercent), charging ? 1 : 0,
            soundEnabled ? 1 : 0, UInt8(clamping: framesPerSecond),
        ]))
    }

    public func hostNetworkResponse(requestID: UInt32, statusCode: Int,
                                    errorCode: Int, body: Data) -> Data {
        var payload = Data()
        append(UInt32(requestID), to: &payload)
        append(UInt32(bitPattern: Int32(clamping: statusCode)), to: &payload)
        append(UInt32(bitPattern: Int32(clamping: errorCode)), to: &payload)
        append(UInt32(body.count), to: &payload)
        payload.append(body)
        return packet(type: 0x21, payload: payload)
    }

    private func append(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private func packet(type: UInt8, payload: Data) -> Data {
        var result = Data([0x53, 0x33, 0x56, 0x44, 0x01, type])
        var length = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        result.append(payload)
        return result
    }
}
