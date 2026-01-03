# Backend

Rust + Actix-web バックエンドサーバー

## 機能

- 環境別データベース対応（SQLite/PostgreSQL/AWS RDS）
- OIDC認証（Keycloak連携、開発環境はダミー認証）
- RESTful API
- CORS対応

## 開発

```bash
# 環境変数設定
cp .env.example .env

# ビルド
cargo build

# 実行
cargo run

# テスト
cargo test
```

## API エンドポイント

- `GET /health` - ヘルスチェック
- `GET /api/auth/info` - 認証情報取得
- `GET /api/users` - ユーザー一覧取得
- `POST /api/users` - ユーザー作成
- `GET /api/users/{id}` - ユーザー詳細取得
- `DELETE /api/users/{id}` - ユーザー削除
