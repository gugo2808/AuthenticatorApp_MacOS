import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var store: AccountStore
    @State private var tick = Date()
    @State private var showAddSheet = false
    @State private var showImportSheet = false
    @State private var copiedID: UUID?
    @State private var showDeleteAllAlert = false
    @State private var editingAccount: TOTPAccount?

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if store.accounts.isEmpty {
                emptyState
            } else {
                accountList
            }
            Divider()
            bottomBar
        }
        .frame(width: 320)
        .onReceive(timer) { _ in tick = Date() }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No accounts yet")
                .font(.headline)
            Text("Add an account to get started.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    // MARK: - Account list

    private var accountList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.accounts) { account in
                    AccountRow(
                        account: account,
                        tick: tick,
                        copiedID: $copiedID,
                        onDelete: { store.delete(id: account.id) },
                        onEdit: { editingAccount = account }
                    )
                    if account.id != store.accounts.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button {
                showAddSheet = true
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Button {
                showImportSheet = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Spacer()

            if !store.accounts.isEmpty {
                Button {
                    showDeleteAllAlert = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Delete all accounts")
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .alert("Delete All Accounts?", isPresented: $showDeleteAllAlert) {
            Button("Delete All", role: .destructive) {
                store.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all \(store.accounts.count) accounts. This cannot be undone.")
        }
        .sheet(isPresented: $showAddSheet) {
            AddAccountView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showImportSheet) {
            ImportView()
                .environmentObject(store)
        }
        .sheet(item: $editingAccount) { account in
            EditAccountView(account: account)
                .environmentObject(store)
        }
    }
}

// MARK: - Account row

struct AccountRow: View {
    let account: TOTPAccount
    let tick: Date
    @Binding var copiedID: UUID?
    var onDelete: () -> Void
    var onEdit: () -> Void

    private var secretData: Data? { Data(base32Encoded: account.secret) }
    private var code: String {
        guard let d = secretData else { return "------" }
        return TOTPEngine.generate(secret: d, digits: account.digits, period: account.period)
    }
    private var secondsLeft: Int { TOTPEngine.secondsRemaining(period: account.period) }
    private var progress: Double { Double(secondsLeft) / Double(account.period) }
    private var isCopied: Bool { copiedID == account.id }

    var body: some View {
        HStack(spacing: 12) {
            // Circular countdown
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(progress < 0.2 ? Color.red : Color.accentColor, lineWidth: 2)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: secondsLeft)
                Text("\(secondsLeft)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(progress < 0.2 ? .red : .primary)
            }
            .frame(width: 32, height: 32)

            // Labels
            VStack(alignment: .leading, spacing: 2) {
                Text(account.issuer.isEmpty ? account.label : account.issuer)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(account.label)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .opacity(account.issuer.isEmpty ? 0 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Code + copy button
            Button {
                copyCode()
            } label: {
                HStack(spacing: 6) {
                    Text(formattedCode)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(isCopied ? .green : .secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { copyCode() }
        .contextMenu {
            Button {
                copyCode()
            } label: {
                Label("Copy Code", systemImage: "doc.on.doc")
            }
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var formattedCode: String {
        // Insert space in the middle for readability
        guard code.count == 6 else { return code }
        return String(code.prefix(3)) + " " + String(code.suffix(3))
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copiedID = account.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedID == account.id { copiedID = nil }
        }
    }
}
