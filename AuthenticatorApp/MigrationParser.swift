import Foundation

// Minimal protobuf binary reader — no dependencies, wire types 0/1/2/5 only.
private struct ProtoReader {
    private let data: Data
    private var pos: Int = 0

    init(_ data: Data) { self.data = data }

    var isEOF: Bool { pos >= data.count }

    mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0
        var shift = 0
        while pos < data.count {
            let byte = data[pos]; pos += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    mutating func readBytes(count: Int) -> Data? {
        guard pos + count <= data.count else { return nil }
        defer { pos += count }
        return data.subdata(in: pos..<(pos + count))
    }

    mutating func readLengthDelimited() -> Data? {
        guard let len = readVarint() else { return nil }
        return readBytes(count: Int(len))
    }

    mutating func skipField(wireType: Int) {
        switch wireType {
        case 0: _ = readVarint()
        case 1: _ = readBytes(count: 8)
        case 2: _ = readLengthDelimited()
        case 5: _ = readBytes(count: 4)
        default: pos = data.count
        }
    }

    mutating func readTag() -> (field: Int, wireType: Int)? {
        guard let v = readVarint() else { return nil }
        return (Int(v >> 3), Int(v & 7))
    }
}

// Batch metadata from a Google Authenticator export QR code.
struct MigrationBatch {
    let accounts: [TOTPAccount]
    let batchId: Int       // same across all QRs in one export session
    let batchIndex: Int    // 0-based index of this QR
    let batchSize: Int     // total number of QR codes in this export

    var isLast: Bool { batchIndex == batchSize - 1 }
    var isSingle: Bool { batchSize <= 1 }
}

// Parses Google Authenticator's `otpauth-migration://offline?data=…` protobuf payload.
enum MigrationParser {
    private static let typeHOTP = 1
    private static let typeTOTP = 2

    // Returns batch metadata + accounts from one QR code payload.
    static func parse(_ data: Data) throws -> MigrationBatch {
        var reader = ProtoReader(data)
        var accounts: [TOTPAccount] = []
        var batchSize  = 1
        var batchIndex = 0
        var batchId    = 0

        while !reader.isEOF {
            guard let tag = reader.readTag() else { break }
            switch tag.field {
            case 1 where tag.wireType == 2:           // otp_parameters (repeated)
                if let msgData = reader.readLengthDelimited(),
                   let account = parseOtpParameters(msgData) {
                    accounts.append(account)
                }
            case 3 where tag.wireType == 0:           // batch_size
                if let v = reader.readVarint() { batchSize  = Int(v) }
            case 4 where tag.wireType == 0:           // batch_index
                if let v = reader.readVarint() { batchIndex = Int(v) }
            case 5 where tag.wireType == 0:           // batch_id
                if let v = reader.readVarint() { batchId    = Int(v) }
            default:
                reader.skipField(wireType: tag.wireType)
            }
        }

        if accounts.isEmpty { throw ImportError.noTOTPAccounts }
        return MigrationBatch(accounts: accounts,
                              batchId: batchId,
                              batchIndex: batchIndex,
                              batchSize: max(1, batchSize))
    }

    private static func parseOtpParameters(_ data: Data) -> TOTPAccount? {
        var reader = ProtoReader(data)
        var secretData: Data?
        var name   = ""
        var issuer = ""
        var digits = 6
        var type   = typeTOTP

        while !reader.isEOF {
            guard let tag = reader.readTag() else { break }
            switch tag.field {
            case 1 where tag.wireType == 2:
                secretData = reader.readLengthDelimited()
            case 2 where tag.wireType == 2:
                if let d = reader.readLengthDelimited() { name   = String(data: d, encoding: .utf8) ?? "" }
            case 3 where tag.wireType == 2:
                if let d = reader.readLengthDelimited() { issuer = String(data: d, encoding: .utf8) ?? "" }
            case 5 where tag.wireType == 0:
                if let v = reader.readVarint() { digits = v == 2 ? 8 : 6 }
            case 6 where tag.wireType == 0:
                if let v = reader.readVarint() { type = Int(v) }
            default:
                reader.skipField(wireType: tag.wireType)
            }
        }

        guard type == typeTOTP, let raw = secretData else { return nil }
        let b32   = raw.base32EncodedString.replacingOccurrences(of: "=", with: "")
        let label = name.isEmpty ? (issuer.isEmpty ? "Unknown" : issuer) : name
        return TOTPAccount(label: label, issuer: issuer, secret: b32, digits: digits, period: 30)
    }
}
