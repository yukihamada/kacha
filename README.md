# KAGI — スマートホーム管理

> 鍵・照明・民泊をまとめて管理。E2E暗号化で安全にシェア。

[![TestFlight](https://img.shields.io/badge/TestFlight-Beta-blue)](https://testflight.apple.com/join/tntB2b27)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

## Features

- **スマートロック** — SwitchBot, Sesame, Nuki, Qrio対応
- **照明制御** — Philips Hue シーン管理
- **Beds24予約同期** — Airbnb/Booking.com予約を自動取得
- **E2E暗号化シェア** — AES-256-GCM、サーバーに平文保存なし
- **チーム管理** — ゲスト/清掃/マネージャー/オーナー代理の4段階
- **複数物件** — スワイプで切り替え、総合ダッシュボード
- **収支レポート** — 月別グラフ、プラットフォーム別内訳
- **バックグラウンド通知** — 新規予約をプッシュ通知
- **オートロック解除** — SwitchBot Botでインターホン遠隔解除
- **ジオフェンス** — 自宅に近づいたら通知

## Architecture

```
iOS (SwiftUI + SwiftData)
├── Local-first — 全データは端末に保存
├── E2E Encryption — CryptoKit AES-256-GCM
├── Keychain Backup — 再インストール後も復元
└── Background Fetch — BGAppRefreshTask

Server (Rust + axum + SQLite)
├── kacha-server.fly.dev / kacha.pasha.run
├── 暗号化blobのみ保存
├── Universal Links (AASA)
└── 期限管理 + 取り消しAPI
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| iOS | SwiftUI, SwiftData, CryptoKit, CoreLocation, Charts |
| Server | Rust, axum 0.7, SQLite (rusqlite), Fly.io |
| Smart Home | SwitchBot API, Sesame API, Philips Hue, Nuki Web API |
| PMS | Beds24 API v2 |
| Security | AES-256-GCM E2E, Keychain, URL fragment key |

## Getting Started

```bash
# Clone
git clone https://github.com/yukihamada/kacha.git
cd kacha/ios

# Generate Xcode project
xcodegen generate

# Build & run on simulator
xcodebuild -project Kacha.xcodeproj -scheme Kacha \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Run tests
xcodebuild test -project Kacha.xcodeproj -scheme Kacha \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:KachaTests
```

## Server

```bash
cd server
cargo run  # localhost:8080
# Deploy
fly deploy --remote-only -a kacha-server
```

## Contributing

PRs welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repo
2. Create a feature branch
3. Make your changes
4. Run tests
5. Submit a PR

## License

MIT

## Links

- [TestFlight Beta](https://testflight.apple.com/join/tntB2b27)
- [kacha.pasha.run](https://kacha.pasha.run) — Universal Links + Privacy + Support
- [enablerdao.com](https://enablerdao.com) — Enabler vision
- [Beds24 API](https://beds24.com/api/v2) — PMS integration docs
