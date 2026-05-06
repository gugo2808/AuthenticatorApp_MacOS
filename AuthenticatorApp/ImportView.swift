import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var store: AccountStore
    @Environment(\.dismiss) var dismiss

    enum Mode: String, CaseIterable { case scan = "Scan QR"; case uri = "Google Auth URI"; case file = "JSON File" }
    @State private var mode: Mode = .scan
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isDragging = false
    @State private var migrationURI = ""
    @State private var cameraPermissionDenied = false

    // Batch scanning state
    @State private var batchId: Int?           // active export session ID
    @State private var batchSize: Int = 1      // total QR codes in current export
    @State private var scannedIndices = Set<Int>() // which QR indices we've already imported
    @State private var totalImported = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Accounts")
                .font(.headline)

            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _ in
                errorMessage = nil; successMessage = nil
                if mode != .scan { resetBatchState() }
            }

            switch mode {
            case .scan: scanForm
            case .uri:  migrationForm
            case .file: fileForm
            }

            if let err = errorMessage {
                Text(err).foregroundColor(.red).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if let msg = successMessage {
                Text(msg).foregroundColor(.green).font(.caption)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    // MARK: - Scan QR tab

    private var scanForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            if cameraPermissionDenied {
                VStack(spacing: 10) {
                    Image(systemName: "camera.slash")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text("Camera access was denied.")
                        .font(.callout)
                    Text("Enable it in System Settings → Privacy & Security → Camera.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
                        )
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                scanInstructions
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ZStack(alignment: .bottom) {
                    QRScannerView(
                        onDetect: { handleScan($0) },
                        onPermissionDenied: { cameraPermissionDenied = true }
                    )
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    scanningStatusLabel
                        .padding(8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                )

                // Batch progress dots (only when a multi-QR export is in progress)
                if batchSize > 1 {
                    batchProgressView
                }
            }
        }
    }

    private var scanInstructions: some View {
        Group {
            if batchSize > 1 {
                let remaining = batchSize - scannedIndices.count
                Text("Scan the next QR code (\(remaining) remaining).")
            } else {
                Text("Point the Mac's camera at a Google Authenticator export QR code.")
            }
        }
    }

    private var scanningStatusLabel: some View {
        Group {
            if batchSize > 1 {
                Text("\(scannedIndices.count) / \(batchSize) scanned")
            } else {
                Text("Scanning…")
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var batchProgressView: some View {
        HStack(spacing: 6) {
            ForEach(0..<batchSize, id: \.self) { idx in
                Circle()
                    .fill(scannedIndices.contains(idx) ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    // MARK: - Google Auth URI tab

    private var migrationForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste an otpauth:// or otpauth-migration:// URI.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $migrationURI)
                .font(.system(.body, design: .monospaced))
                .frame(height: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                )
                .overlay(
                    Group {
                        if migrationURI.isEmpty {
                            Text("otpauth-migration://offline?data=…")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(4)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )

            Button("Import from URI") { importMigration() }
                .buttonStyle(.bordered)
                .disabled(migrationURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - JSON file tab

    private var fileForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drop a JSON file containing your TOTP accounts, or click to choose.")
                .font(.caption)
                .foregroundColor(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isDragging ? Color.accentColor : Color.secondary.opacity(0.4),
                                  style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(isDragging ? Color.accentColor.opacity(0.08) : Color.clear))

                VStack(spacing: 8) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 28))
                        .foregroundColor(isDragging ? .accentColor : .secondary)
                    Text("Drop JSON file here")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Button("Choose File…") { chooseFile() }
                        .buttonStyle(.bordered)
                }
            }
            .frame(height: 110)
            .onDrop(of: [.json, .fileURL], isTargeted: $isDragging) { handleDrop(providers: $0) }
        }
    }

    // MARK: - QR Scan handling (supports batch exports)

    private func handleScan(_ payload: String) {
        errorMessage = nil; successMessage = nil

        if payload.hasPrefix("otpauth-migration://") {
            do {
                let batch = try store.importMigrationBatch(payload)

                // Track which batch ID is active; reset if a new export session starts
                if batchId != batch.batchId {
                    resetBatchState()
                    batchId   = batch.batchId
                    batchSize = batch.batchSize
                    totalImported = 0
                }

                // Skip duplicates (user re-scanned same QR)
                guard !scannedIndices.contains(batch.batchIndex) else { return }
                scannedIndices.insert(batch.batchIndex)
                totalImported += batch.accounts.count

                if scannedIndices.count == batchSize {
                    // All QRs in this export have been scanned
                    successMessage = "All \(batchSize) QR codes scanned — imported \(totalImported) accounts"
                    resetBatchState()
                    mode = .uri
                } else {
                    let remaining = batchSize - scannedIndices.count
                    successMessage = "\(batch.accounts.count) accounts added — scan \(remaining) more QR code\(remaining == 1 ? "" : "s")"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            // Single otpauth://totp/ QR code
            do {
                let before = store.accounts.count
                try store.importURI(payload)
                let added = store.accounts.count - before
                successMessage = "Imported \(added) account\(added == 1 ? "" : "s")"
                mode = .uri
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resetBatchState() {
        batchId = nil; batchSize = 1; scannedIndices = []; totalImported = 0
    }

    // MARK: - URI paste handling

    private func importMigration() {
        errorMessage = nil; successMessage = nil
        let uri = migrationURI.trimmingCharacters(in: .whitespacesAndNewlines)
        let before = store.accounts.count
        do {
            try store.importURI(uri)
            let added = store.accounts.count - before
            successMessage = "Imported \(added) account\(added == 1 ? "" : "s")"
            migrationURI = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - File import

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { processFile(url: url) }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        let id = UTType.json.identifier
        if provider.hasItemConformingToTypeIdentifier(id) {
            provider.loadItem(forTypeIdentifier: id) { item, _ in
                DispatchQueue.main.async {
                    if let url  = item as? URL  { self.processFile(url: url) }
                    else if let d = item as? Data { self.processData(d) }
                }
            }
            return true
        } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let d = item as? Data, let url = URL(dataRepresentation: d, relativeTo: nil) {
                    DispatchQueue.main.async { self.processFile(url: url) }
                }
            }
            return true
        }
        return false
    }

    private func processFile(url: URL) {
        guard let data = try? Data(contentsOf: url) else { errorMessage = "Could not read file"; return }
        processData(data)
    }

    private func processData(_ data: Data) {
        errorMessage = nil; successMessage = nil
        let before = store.accounts.count
        do {
            try store.importJSON(data)
            let added = store.accounts.count - before
            successMessage = "Imported \(added) account\(added == 1 ? "" : "s")"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
