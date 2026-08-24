# Spendly

Spendly is a production-oriented iOS 17+ application with a Supabase backend and a transport-only reverse proxy. This repository is the monorepo for the SwiftUI client, database migrations and policies, Edge Functions, proxy configuration, tests, and operational documentation.

## Toolchain

- Xcode 26.6 (build 17F113)
- Apple Swift 6.3.3
- Supabase CLI 2.115.0
- Docker 29.5.2
- XcodeGen 2.46.0
- iOS Simulator Runtime 26.5

The machine currently selects Command Line Tools globally. Until an administrator runs `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`, prefix Xcode commands with:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## Generate the Xcode project

```bash
xcodegen generate
```

No production credentials belong in this repository. Client traffic must use `https://api.spendly.app`; direct production access to Supabase project hosts is prohibited.

