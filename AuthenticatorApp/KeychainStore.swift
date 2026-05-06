import Foundation
import Security

struct TOTPAccount: Identifiable, Codable {
    var id: UUID
    var label: String
    var issuer: String
    var secret: String   // base32
    var digits: Int
    var period: Int

    init(id: UUID = UUID(), label: String, issuer: String, secret: String, digits: Int = 6, period: Int = 30) {
        self.id = id
        self.label = label
        self.issuer = issuer
        self.secret = secret
        self.digits = digits
        self.period = period
    }
}

enum KeychainStore {
    private static let service = "com.authenticatorapp.totp"
    private static let accountKey = "accounts"

    static func load() -> [TOTPAccount] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: accountKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return [] }
        return (try? JSONDecoder().decode([TOTPAccount].self, from: data)) ?? []
    }

    static func save(_ accounts: [TOTPAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: accountKey
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
