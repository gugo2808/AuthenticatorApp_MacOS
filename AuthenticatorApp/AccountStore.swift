import Foundation
import Combine

final class AccountStore: ObservableObject {
    @Published var accounts: [TOTPAccount] = []

    init() {
        accounts = KeychainStore.load()
    }

    func add(_ account: TOTPAccount) {
        // Skip silently if the same secret is already stored
        guard !accounts.contains(where: { $0.secret == account.secret }) else { return }
        accounts.append(account)
        persist()
    }

    func update(_ account: TOTPAccount) {
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[idx] = account
        persist()
    }

    func delete(at offsets: IndexSet) {
        accounts.remove(atOffsets: offsets)
        persist()
    }

    func delete(id: UUID) {
        accounts.removeAll { $0.id == id }
        persist()
    }

    func deleteAll() {
        accounts.removeAll()
        persist()
    }

    private func persist() {
        KeychainStore.save(accounts)
    }

    // MARK: - Import

    // Used by URI tab paste flow (single account or migration).
    func importURI(_ uri: String) throws {
        if uri.hasPrefix("otpauth-migration://") {
            let batch = try parseMigrationBatch(uri)
            batch.accounts.forEach { add($0) }
        } else {
            let account = try parseOTPAuthURI(uri)
            add(account)
        }
    }

    // Used by QR scanner — returns MigrationBatch so caller can track progress.
    @discardableResult
    func importMigrationURI(_ uri: String) throws -> Int {
        let batch = try parseMigrationBatch(uri)
        batch.accounts.forEach { add($0) }
        return batch.accounts.count
    }

    // Returns full batch metadata (accounts + batchId/Index/Size).
    func importMigrationBatch(_ uri: String) throws -> MigrationBatch {
        let batch = try parseMigrationBatch(uri)
        batch.accounts.forEach { add($0) }
        return batch
    }

    private func parseMigrationBatch(_ uri: String) throws -> MigrationBatch {
        // URLComponents correctly percent-decodes %2B → + (not space)
        guard let comps = URLComponents(string: uri),
              comps.scheme == "otpauth-migration" else {
            throw ImportError.invalidURI
        }
        guard let dataParam = comps.queryItems?.first(where: { $0.name == "data" })?.value else {
            throw ImportError.missingSecret
        }
        guard let protoData = Data(base64Encoded: dataParam, options: .ignoreUnknownCharacters) else {
            throw ImportError.invalidData
        }
        return try MigrationParser.parse(protoData)
    }

    func importJSON(_ data: Data) throws {
        struct JSONEntry: Decodable {
            var label: String?
            var name: String?
            var issuer: String?
            var secret: String
            var digits: Int?
            var period: Int?
        }
        // Accept both a single object and an array
        let entries: [JSONEntry]
        if let arr = try? JSONDecoder().decode([JSONEntry].self, from: data) {
            entries = arr
        } else {
            entries = [try JSONDecoder().decode(JSONEntry.self, from: data)]
        }
        for e in entries {
            let account = TOTPAccount(
                label: e.label ?? e.name ?? "Unknown",
                issuer: e.issuer ?? "",
                secret: e.secret.uppercased().replacingOccurrences(of: " ", with: ""),
                digits: e.digits ?? 6,
                period: e.period ?? 30
            )
            add(account)
        }
    }

    private func parseOTPAuthURI(_ uri: String) throws -> TOTPAccount {
        guard let url = URL(string: uri),
              url.scheme == "otpauth",
              url.host == "totp" else {
            throw ImportError.invalidURI
        }
        let rawLabel = url.path.dropFirst() // remove leading "/"
        let label = rawLabel.removingPercentEncoding ?? String(rawLabel)
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let params = comps?.queryItems ?? []
        func param(_ name: String) -> String? {
            params.first { $0.name == name }?.value
        }
        guard let secret = param("secret") else { throw ImportError.missingSecret }
        let issuer = param("issuer") ?? ""
        let digits = Int(param("digits") ?? "6") ?? 6
        let period = Int(param("period") ?? "30") ?? 30
        return TOTPAccount(label: label, issuer: issuer, secret: secret.uppercased(), digits: digits, period: period)
    }
}

enum ImportError: LocalizedError {
    case invalidURI, missingSecret, invalidData, noTOTPAccounts

    var errorDescription: String? {
        switch self {
        case .invalidURI:       return "Invalid URI — expected otpauth:// or otpauth-migration://"
        case .missingSecret:    return "URI is missing the secret parameter"
        case .invalidData:      return "Could not decode the migration data (invalid base64)"
        case .noTOTPAccounts:   return "No TOTP accounts found in the migration payload"
        }
    }
}
