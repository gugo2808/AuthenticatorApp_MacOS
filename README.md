# AuthenticatorApp

A native macOS menu bar TOTP authenticator — no Electron, no subscriptions, no cloud. Your secrets stay in the macOS Keychain.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue?logo=apple) ![Swift 5](https://img.shields.io/badge/Swift-5-orange?logo=swift) ![License Non-Commercial](https://img.shields.io/badge/license-Non--Commercial-red) ![No dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

---

## Features

- **Live TOTP codes** with a circular countdown ring that turns red in the last 6 seconds
- **One-click copy** — tap any code or the copy icon; a checkmark confirms
- **QR scanner** — point your Mac's camera at a Google Authenticator export QR code to import directly
- **Batch export support** — scans multiple QR codes from a single Google Authenticator export session with progress tracking
- **otpauth:// URI import** — paste a standard `otpauth://totp/…` or `otpauth-migration://` URI
- **JSON import** — drag-and-drop a JSON file with your accounts
- **Edit & delete** — right-click any account to copy, edit, or delete; trash icon removes all
- **Keychain storage** — secrets are encrypted at rest using the macOS Keychain
- **Zero dependencies** — pure Swift, SwiftUI, AVFoundation, Vision, CryptoKit

---

## Screenshots

> _Add screenshots here after first launch._

---

## Download

**No Xcode needed.** Grab the latest `.dmg` from the [Releases](https://github.com/gugo2808/AuthenticatorApp_MacOS/releases) page, open it, and drag the app to your Applications folder.

---

## Requirements

| | |
|---|---|
| macOS | 13 Ventura or later |
| Xcode | 15 or later |
| Swift | 5.9 or later |

---

## Building

```bash
git clone https://github.com/YOUR_USERNAME/AuthenticatorApp.git
cd AuthenticatorApp
open AuthenticatorApp.xcodeproj
```

Select the **AuthenticatorApp** scheme, choose your Mac as the run destination, and press **⌘R**.

> No third-party package manager setup required — the project has zero external dependencies.

---

## Usage

### Importing accounts

| Method | How |
|---|---|
| **QR scan** | Open Import → Scan QR, point camera at a Google Authenticator export QR |
| **Batch QR** | Scan each QR code in sequence; progress dots track which ones are done |
| **URI paste** | Open Import → Google Auth URI, paste an `otpauth://` or `otpauth-migration://` URI |
| **JSON file** | Open Import → JSON File, drop a `.json` file with your accounts |

#### JSON format

```json
[
  {
    "issuer": "GitHub",
    "label": "user@example.com",
    "secret": "BASE32SECRET",
    "digits": 6,
    "period": 30
  }
]
```

### Managing accounts

| Action | How |
|---|---|
| Copy code | Click the code, or right-click → Copy Code |
| Edit account | Right-click → Edit |
| Delete one | Right-click → Delete |
| Delete all | Trash icon in the bottom bar |

---

## Architecture

```
AuthenticatorApp/
├── AppDelegate.swift        # NSStatusItem + NSPopover setup
├── TOTPEngine.swift         # RFC 6238 TOTP + Base32 codec (no CryptoKit dependency)
├── KeychainStore.swift      # Keychain read/write for [TOTPAccount]
├── AccountStore.swift       # ObservableObject — import, add, edit, delete
├── MigrationParser.swift    # Minimal protobuf decoder for GA migration payloads
├── QRScannerView.swift      # AVFoundation + Vision QR detection (NSViewRepresentable)
├── MenuBarView.swift        # Main popover UI + AccountRow
├── AddAccountView.swift     # Add account sheet (URI or manual)
├── EditAccountView.swift    # Edit account sheet
└── ImportView.swift         # Import sheet (Scan QR / URI / JSON)
```

**TOTP** is computed with `CryptoKit.HMAC<Insecure.SHA1>` per RFC 6238. Secrets are stored as Base32 strings in the Keychain and decoded to raw bytes only at code-generation time.

**Google Authenticator migration** format is a protobuf binary payload base64-encoded in the `data=` query parameter of `otpauth-migration://` URIs. The parser is hand-rolled (no protobuf library) and handles the `batch_id`/`batch_index`/`batch_size` fields for multi-QR exports.

---

## Privacy

- No network requests, ever
- No analytics or telemetry
- Camera is used only while the Import → Scan QR tab is open; it stops the moment you switch tabs or close the sheet
- All account data lives exclusively in the local macOS Keychain

---

## License

Custom Non-Commercial License — see [LICENSE](LICENSE) for details.

Free to use, study, modify, and share. **You may not sell this software or use it for any commercial purpose.**
