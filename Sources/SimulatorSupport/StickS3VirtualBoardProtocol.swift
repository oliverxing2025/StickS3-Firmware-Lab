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

public struct StickS3VirtualBoardCapabilities: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let display = Self(rawValue: 1 << 0)
    public static let buttons = Self(rawValue: 1 << 1)
    public static let bmi270 = Self(rawValue: 1 << 2)
}

public enum StickS3VirtualBoardEvent: Equatable, Sendable {
    case ready(StickS3VirtualBoardCapabilities)
    case frame(StickS3VirtualBoardFrame)
    case log(Data)
}

public struct StickS3VirtualBoardStreamParser: Sendable {
    private static let magic = Data([0x53, 0x33, 0x56, 0x44]) // S3VD
    private static let headerSize = 10
    private static let maximumPayloadSize = 1_048_576
    private var buffer = Data()

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
            case 0x01 where payload.count >= 1:
                events.append(.ready(StickS3VirtualBoardCapabilities(rawValue: readByte(payload, at: 0))))
            case 0x02 where payload.count >= 8:
                let width = Int(readUInt16LE(payload, at: 0))
                let height = Int(readUInt16LE(payload, at: 2))
                let sequence = readUInt32LE(payload, at: 4)
                let pixels = payload.dropFirst(8)
                if width > 0, height > 0, width * height * 2 == pixels.count {
                    events.append(.frame(StickS3VirtualBoardFrame(
                        width: width, height: height, sequence: sequence, rgb565: Data(pixels))))
                }
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

    private func packet(type: UInt8, payload: Data) -> Data {
        var result = Data([0x53, 0x33, 0x56, 0x44, 0x01, type])
        var length = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        result.append(payload)
        return result
    }
}
