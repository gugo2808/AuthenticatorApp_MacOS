import SwiftUI

struct AddAccountView: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) var dismiss

    @State private var uriText = ""
    @State private var issuer = ""
    @State private var label = ""
    @State private var secret = ""
    @State private var digits = 6
    @State private var period = 30
    @State private var errorMessage: String?
    @State private var mode: Mode = .uri

    enum Mode: String, CaseIterable {
        case uri = "URI"
        case manual = "Manual"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Account")
                .font(.headline)

            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)

            if mode == .uri {
                uriForm
            } else {
                manualForm
            }

            if let err = errorMessage {
                Text(err).foregroundColor(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { add() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var uriForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste an otpauth://totp/… URI from your account's security settings.")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("otpauth://totp/…", text: $uriText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }

    private var manualForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Issuer").frame(width: 60, alignment: .trailing)
                TextField("e.g. GitHub", text: $issuer).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Label").frame(width: 60, alignment: .trailing)
                TextField("e.g. user@example.com", text: $label).textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Secret").frame(width: 60, alignment: .trailing)
                TextField("Base32 secret", text: $secret).textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            HStack {
                Text("Digits").frame(width: 60, alignment: .trailing)
                Picker("", selection: $digits) {
                    Text("6").tag(6)
                    Text("8").tag(8)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                Spacer()
            }
            HStack {
                Text("Period").frame(width: 60, alignment: .trailing)
                Picker("", selection: $period) {
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                Spacer()
            }
        }
    }

    private func add() {
        errorMessage = nil
        do {
            if mode == .uri {
                try store.importURI(uriText.trimmingCharacters(in: .whitespaces))
            } else {
                let trimmedSecret = secret.uppercased().replacingOccurrences(of: " ", with: "")
                guard !trimmedSecret.isEmpty else { throw ImportError.missingSecret }
                guard !label.isEmpty else {
                    errorMessage = "Label is required"
                    return
                }
                guard Data(base32Encoded: trimmedSecret) != nil else {
                    errorMessage = "Invalid base32 secret"
                    return
                }
                store.add(TOTPAccount(label: label, issuer: issuer, secret: trimmedSecret, digits: digits, period: period))
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
