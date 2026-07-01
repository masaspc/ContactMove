# ContactMove — iOS 電話帳移行アプリ

連絡先の「端末間ダイレクト転送(Bluetooth/Wi-Fi)」「CSV/vCard 入出力」「重複検出・統合」を、
外部サーバーを一切使わず完全ローカルで行う iOS アプリです。詳細仕様は
[docs/仕様書.md](docs/仕様書.md) を参照してください。

- 対象OS: iOS 16.0+ / 開発: Swift 5.10+, SwiftUI, Xcode 16+
- 外部依存: なし(ゼロ依存方針)
- プライバシー: データ収集ゼロ。連絡先データは端末外(P2P転送の相手端末を除く)へ出ません

## 主な機能

| 機能 | 説明 |
|---|---|
| 端末間転送 | MultipeerConnectivity による近接P2P転送(暗号化必須+4桁確認コード照合、チャンク+SHA-256検証+再送) |
| CSVエクスポート | UTF-8 BOM付き・RFC 4180 準拠。Excel(日本語環境)で文字化けしない |
| CSVインポート | 文字コード自動判定(UTF-8/Shift_JIS/EUC-JP)、Google/Outlook形式の自動判定、カラムマッピング、プレビュー |
| vCard入出力 | .vcf(画像含む)の書き出し・取り込み |
| 重複統合 | 電話E.164正規化/メール/氏名による段階マッチング(L1〜L4)、スキップ/マージ/上書き/両方残す |
| 端末内重複整理 | 既存連絡先のスキャン→グループ表示→マージ実行 |

## Mac での動作確認手順

1. **必要環境**: macOS + Xcode 16 以上(iOS 18 SDK / iPhone シミュレータ)
2. リポジトリを clone して `ContactMove.xcodeproj` を Xcode で開く
3. スキーム `ContactMove`、実行先に任意の iPhone シミュレータを選択して **⌘R**
   - シミュレータの「連絡先」アプリに数件登録しておくと動作確認しやすいです
   - シミュレータでは MultipeerConnectivity のピア発見が不安定なため、端末間転送の
     完全な確認は **実機2台**(同一Wi-Fi または Bluetooth ON)で行ってください
4. ロジックのユニットテスト:
   ```bash
   cd ContactMoveKit && swift test        # または scripts/test.sh
   ```
5. 実機で動かす場合: TARGETS → ContactMove → Signing & Capabilities で
   ご自身の Team を選択(Bundle ID `com.masaspc.contactmove` は必要に応じて変更)

### 動作確認チェックリスト(シミュレータ)

- [ ] 初回起動でオンボーディング(3枚)→ プライバシー方針 → ホームが表示される
- [ ] 「CSV/vCard → エクスポート」で連絡先権限ダイアログ → CSV保存 → Numbers/Excelで開ける
- [ ] 保存したCSVを「インポート」で選択 → プレビュー(件数/サンプル)→ 取り込み → 結果レポート
- [ ] 同じCSVを再インポート → 重複が検出され、戦略「スキップ」で全件スキップになる(冪等性)
- [ ] 「重複整理」で意図的に作った重複がグループ表示され、マージできる
- [ ] 設定 → 画像転送/既定の統合戦略の変更が保持される

## リポジトリ構成

```
ContactMove.xcodeproj   … アプリプロジェクト(Xcode 16 フォルダ同期方式)
App/                    … SwiftUI アプリ本体(Features: Home/Transfer/CSV/Dedupe/Settings)
Support/Info.plist      … 権限記述(連絡先/ローカルネットワーク/Bluetooth/Bonjour)
ContactMoveKit/         … ローカル Swift Package
  Models / CSVKit / DedupeKit / ContactsKit / TransferKit(+ 各テスト)
docs/仕様書.md          … 詳細仕様書 v1.0
scripts/test.sh         … テスト+シミュレータビルド一括実行
```

## 既知の制約(仕様書 §3, §7, 付録A)

- アプリが入っていない端末から Bluetooth で連絡先を「吸い出す」ことは iOS の制約上不可能
  (PBAP/OPP 非開放)。vCard + AirDrop / CSV + クラウド共有の導線を用意しています
- 連絡先の「メモ」フィールドは Apple の Entitlement 承認が必要なため MVP では非対応
- iOS 18 の「限定アクセス」中は全件移行不可 → アプリ内バナーで設定変更を誘導
- 転送はフォアグラウンド前提(転送中は画面スリープを自動抑止)
