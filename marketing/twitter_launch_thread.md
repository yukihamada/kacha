# X/Twitter Launch Thread

投稿アカウント: @enablerdao
ハッシュタグ: #KAGI #民泊 #スマートロック #Beds24 #民泊管理

---

## Tweet 1/7 (Hook)

KAGI（カギ）— 民泊管理の手間を10分の1にするiOSアプリをリリースしました。

Beds24連携 × スマートロック × AIゲスト返信。

全てiPhoneだけで完結します。

しかもオープンソース（MIT）。

https://testflight.apple.com/join/CTmyqV6H

---

## Tweet 2/7 (Problem)

民泊ホストの日常:

- 深夜3時に「鍵が開かない」とメッセージ
- チェックイン/アウトの度にドアコードを手動変更
- Booking.comとAirbnbのメッセージを別々にチェック
- 清掃スタッフにいちいちLINEで鍵情報を送る

全部やってました。3年間。

---

## Tweet 3/7 (Solution)

KAGIの解決策:

1. Beds24のInvite Codeを入力 → 全予約が自動同期
2. スマートロックを登録 → ワンタップで解錠
3. ゲストメッセージが届く → AIが返信候補を3つ提案 → タップで送信
4. ゲストカードを自動生成 → WiFi、ドアコード、ハウスルールを暗号化リンクで共有

設定は10分。あとは自動。

---

## Tweet 4/7 (Tech)

技術的なこだわり:

- SwiftUI + SwiftData でネイティブiOS
- サーバーはRust (axum) + SQLite on Fly.io
- E2E暗号化: AES-256-GCM、サーバーにも平文が残らない
- ローカルファースト: データは全てiPhoneに保存
- オープンソース: https://github.com/yukihamada/kacha

ゲストの個人情報を預からないことが、最大のセキュリティ。

---

## Tweet 5/7 (Devices)

対応スマートロック:

- SwitchBot ロック / Bot（オートロック解除にも対応）
- Sesame 5 / 5 Pro
- Nuki Smart Lock
- Qrio Lock

照明:
- Philips Hue（シーン管理、チェックイン時の自動点灯）

他にも対応してほしいデバイスがあれば教えてください。

---

## Tweet 6/7 (Pricing)

料金:

Free: 1物件、全機能使えます
Pro: ¥980/月（複数物件、E2Eシェア、バックグラウンド同期、チーム管理）

ローカル機能は全て無料。サーバーを使う機能だけ有料。

まずは1物件で試してみてください。

---

## Tweet 7/7 (CTA)

TestFlightで今すぐ試せます:
https://testflight.apple.com/join/CTmyqV6H

フィードバック大歓迎です。

- どのスマートロックを使ってるか
- 民泊管理で一番面倒なこと
- 欲しい機能

リプ、DM、GitHubのIssue、なんでもOKです。

一緒に民泊管理をラクにしましょう。
