# CI/CD 事前チェックガイド

このドキュメントでは、GitHub Actions CI/CD にプッシュする前に、ローカルで同じチェックを実行する方法を説明します。

## なぜ CI/CD 事前チェックが必要か？

- ❌ プッシュ後に CI/CD が失敗すると、修正 → 再プッシュのサイクルが必要
- ✅ 事前にローカルでチェックすれば、CI/CD の失敗を防げる
- ⚡ 時間の節約：ローカルでのチェックの方が高速
- 💡 早期発見：問題を早く見つけて修正できる

## 使い方

### 方法 1: Make コマンド（推奨）

プロジェクトルートで以下を実行：

```bash
# すべてのCI/CDチェックを実行
make ci-check

# バックエンドのみ
make ci-backend

# フロントエンドのみ
make ci-frontend
```

### 方法 2: スクリプト

```bash
./scripts/ci-check.sh
```

## チェック内容

### Backend CI Checks (`make ci-backend`)

1. **Tests** - `cargo test --verbose`
   - すべてのユニットテストと統合テストを実行
2. **Clippy** - `cargo clippy -- -D warnings`
   - Rust のコード品質チェック
   - 警告があるとエラーとして扱われます

### Frontend CI Checks (`make ci-frontend`)

1. **Install** - `npm ci`
   - 依存関係をクリーンインストール
2. **Lint** - `npm run lint`
   - ESLint でコードスタイルとエラーをチェック
   - TypeScript の型エラーもチェック
3. **Test** - `npm test -- --run`
   - Vitest でユニットテストを実行
4. **Build** - `npm run build`
   - プロダクションビルドが成功するか確認

## 出力例

成功時:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🦀 Backend CI Checks
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ️  Running cargo test...
✅ Backend tests passed
ℹ️  Running cargo clippy...
✅ Backend clippy checks passed

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⚛️  Frontend CI Checks
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ℹ️  Installing dependencies...
✅ Dependencies installed
ℹ️  Running linter...
✅ Frontend linting passed
ℹ️  Running tests...
✅ Frontend tests passed
ℹ️  Building frontend...
✅ Frontend build successful

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📊 Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ All CI checks passed! ✨
ℹ️  Your code is ready to push. CI/CD should pass successfully.
```

失敗時:

```
❌ Backend tests failed
⚠️  Please fix the errors above before pushing.
```

## ワークフロー例

### 新機能開発時

1. コードを書く
2. `make ci-check` でローカル検証
3. エラーがあれば修正
4. すべて通ったらコミット & プッシュ
5. GitHub Actions の CI/CD が自動的にパス ✅

```bash
# コード変更後
git add .
git commit -m "feat: add new feature"

# CI/CDチェック
make ci-check

# すべて通ったらプッシュ
git push origin feature-branch
```

### バックエンドのみ変更した場合

```bash
# バックエンドだけチェック（高速）
make ci-backend

# 問題なければプッシュ
git push
```

### フロントエンドのみ変更した場合

```bash
# フロントエンドだけチェック
make ci-frontend

# 問題なければプッシュ
git push
```

## トラブルシューティング

### Q: `make ci-check`が失敗する

A: エラーメッセージを確認して修正してください。よくある原因：

- **Clippy 警告**: コードの品質問題

  ```bash
  # 警告の詳細を確認
  cd backend && cargo clippy
  ```

- **Lint エラー**: コードスタイルの問題

  ```bash
  # 自動修正を試す
  cd frontend && npm run lint -- --fix
  ```

- **テスト失敗**: ロジックの問題
  ```bash
  # 詳細なテスト結果を確認
  cd backend && cargo test
  cd frontend && npm test
  ```

### Q: CI/CD は通るけどローカルでは失敗する

A: 依存関係が古い可能性があります：

```bash
# Rust
cd backend && cargo clean && cargo build

# Node.js
cd frontend && rm -rf node_modules package-lock.json
npm install
```

### Q: ローカルでは通るけど CI/CD が失敗する

A: 以下を確認：

1. Gitignore されたファイルをコミットし忘れていないか
2. 環境依存のコードがないか
3. `npm ci`と`npm install`の違い（CI/CD は`npm ci`を使用）

## Git Hooks での自動チェック（オプション）

プッシュ前に自動でチェックを実行する設定：

```bash
# .git/hooks/pre-push ファイルを作成
cat > .git/hooks/pre-push << 'EOF'
#!/bin/bash
echo "Running CI checks before push..."
./scripts/ci-check.sh
EOF

chmod +x .git/hooks/pre-push
```

これで`git push`時に自動的に CI/CD チェックが実行されます。

## まとめ

- ✅ プッシュ前に必ず`make ci-check`を実行
- ⚡ 部分的な変更なら`make ci-backend`または`make ci-frontend`
- 🔧 失敗したら修正 → 再チェック → プッシュ
- 🎯 すべて通れば CI/CD も必ず成功
