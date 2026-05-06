import Foundation
import CryptoKit

struct TOTPEngine {
    static func generate(secret: Data, digits: Int = 6, period: Int = 30) -> String {
        let counter = UInt64(Date().timeIntervalSince1970) / UInt64(period)
        return hotp(secret: secret, counter: counter, digits: digits)
    }

    static func secondsRemaining(period: Int = 30) -> Int {
        let epoch = Int(Date().timeIntervalSince1970)
        return period - (epoch % period)
    }

    private static func hotp(secret: Data, counter: UInt64, digits: Int) -> String {
        var bigEndian = counter.bigEndian
        let counterData = Data(bytes: &bigEndian, count: 8)
        let key = SymmetricKey(data: secret)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key)
        let hmacData = Data(mac)
        let offset = Int(hmacData[19] & 0x0f)
        let truncated = hmacData.subdata(in: offset..<(offset + 4))
        var code = truncated.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        code &= 0x7fffffff
        code = code % UInt32(pow(10.0, Double(digits)))
        return String(format: "%0\(digits)d", code)
    }
}

// MARK: - Base32 codec (RFC 4648)
extension Data {
    var base32EncodedString: String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var result = ""
        var buffer = 0
        var bitsInBuffer = 0
        for byte in self {
            buffer = (buffer << 8) | Int(byte)
            bitsInBuffer += 8
            while bitsInBuffer >= 5 {
                bitsInBuffer -= 5
                result.append(alphabet[(buffer >> bitsInBuffer) & 0x1f])
            }
        }
        if bitsInBuffer > 0 {
            result.append(alphabet[(buffer << (5 - bitsInBuffer)) & 0x1f])
        }
        while result.count % 8 != 0 { result.append("=") }
        return result
    }

    init?(base32Encoded string: String) {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let cleaned = string.uppercased().replacingOccurrences(of: "=", with: "")
        var bits = 0
        var bitsCount = 0
        var result = Data()
        for char in cleaned {
            guard let idx = alphabet.firstIndex(of: char) else { return nil }
            let value = alphabet.distance(from: alphabet.startIndex, to: idx)
            bits = (bits << 5) | value
            bitsCount += 5
            if bitsCount >= 8 {
                bitsCount -= 8
                result.append(UInt8((bits >> bitsCount) & 0xff))
            }
        }
        self = result
    }
}
