import SwiftUI

struct EditAccountView: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) var dismiss

    let account: TOTPAccount

    @State private var issuer: String
    @State private var label: String
    @State private var secret: String
    @State private var digits: Int
    @State private var period: Int
    @State private var errorMessage: String?

    init(account: TOTPAccount) {
        self.account = account
        _issuer  = State(initialValue: account.issuer)
        _label   = State(initialValue: account.label)
        _secret  = State(initialValue: account.secret)
        _digits  = State(initialValue: account.digits)
        _period  = State(initialValue: account.period)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Account")
                .font(.headline)

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
                    TextField("Base32 secret", text: $secret)
                        .textFieldStyle(.roundedBorder)
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

            if let err = errorMessage {
                Text(err).foregroundColor(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        let trimmedSecret = secret.uppercased().replacingOccurrences(of: " ", with: "")
        guard !label.isEmpty else { errorMessage = "Label is required"; return }
        guard Data(base32Encoded: trimmedSecret) != nil else { errorMessage = "Invalid base32 secret"; return }
        var updated = account
        updated.issuer = issuer
        updated.label  = label
        updated.secret = trimmedSecret
        updated.digits = digits
        updated.period = period
        store.update(updated)
        dismiss()
    }
}
