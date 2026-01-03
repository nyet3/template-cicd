# Keycloak Configuration

このディレクトリには、Keycloak の設定とセットアップスクリプトが含まれています。

## ファイル

### idp-entrypoint.sh

Keycloak コンテナの起動時に実行されるエントリーポイントスクリプト。以下の処理を実行します：

1. HTTPS 用の自己署名証明書を生成
2. Keycloak サーバーを起動
3. レアルムセットアップスクリプトを実行
4. 外部 IdP（Entra ID）の設定（環境変数が設定されている場合）

### setup-realm.sh

レアルム、ユーザー、ロール、クライアントを自動設定するスクリプト。以下を作成します：

#### レアルム

- **testrealm**: メインのテストレアルム

#### ロール

- **admin**: 管理者ロール
- **manager**: マネージャーロール
- **user**: 一般ユーザーロール
- **viewer**: 閲覧者ロール
- **editor**: 編集者ロール

#### グループ

- **Administrators**: 管理者グループ（ロール: admin, manager）
- **Developers**: 開発者グループ（ロール: user, editor）
- **Managers**: マネージャーグループ（ロール: manager, user）
- **Operations**: 運用チームグループ（ロール: user）
- **Viewers**: 閲覧者グループ（ロール: viewer）
- **Beginners**: 初心者グループ（ロール: beginner - ログインのみ可能）

#### クライアント

- **backend-client**: バックエンドサービス用（confidential client）
- **frontend-client**: フロントエンドアプリケーション用（public client）

#### サンプルユーザー

| ユーザー名 | メール               | パスワード  | グループ       | ロール（グループから継承） | 説明                           |
| ---------- | -------------------- | ----------- | -------------- | -------------------------- | ------------------------------ |
| admin      | admin@example.com    | admin123    | Administrators | admin, manager             | 管理者ユーザー                 |
| testuser   | test@example.com     | testpass123 | Developers     | user, editor               | 開発者テストユーザー           |
| manager    | manager@example.com  | manager123  | Managers       | manager, user              | マネージャーユーザー           |
| viewer     | viewer@example.com   | viewer123   | Viewers        | viewer                     | 閲覧専用ユーザー               |
| beginner   | beginner@example.com | beginner123 | Beginners      | beginner                   | 初心者ユーザー（ログインのみ） |

### realm-export.json

レアルムの基本設定を含むエクスポートファイル（後方互換性のため保持）。
`setup-realm.sh`スクリプトが優先されます。

## 使用方法

### 基本的な起動

```bash
docker compose up -d keycloak
```

Keycloak は起動時に自動的に以下を実行します：

1. HTTPS キーストアの生成（初回のみ）
2. レアルムとユーザーのセットアップ
3. 必要に応じて Entra ID（Azure AD）の設定

### 設定のカスタマイズ

環境変数ファイル（`env/test/keycloak.env`など）を編集して、以下をカスタマイズできます：

```bash
KC_REALM=testrealm                          # レアルム名
BACKEND_CLIENT_SECRET=your-secret-here      # バックエンドクライアントのシークレット
KEYCLOAK_ADMIN=admin                        # 管理者ユーザー名
KEYCLOAK_ADMIN_PASSWORD=admin               # 管理者パスワード
```

### 外部 IdP（Entra ID / Azure AD）の設定

`env/test/idp.env`に以下を設定します：

```bash
ENTRA_TENANT_ID=your-tenant-id
ENTRA_CLIENT_ID=your-client-id
ENTRA_CLIENT_SECRET=your-client-secret
ENTRA_ALIAS=entra-id
ENTRA_DISPLAY_NAME=Entra ID
ENTRA_SCOPES=openid profile email
```

## アクセス

- **Admin Console**: https://localhost:8443/admin/

  - ユーザー名: `admin`
  - パスワード: `admin`

- **Account Console**: https://localhost:8443/realms/testrealm/account/

  - 上記のサンプルユーザーでログイン可能

- **Token Endpoint**: https://localhost:8443/realms/testrealm/protocol/openid-connect/token
- **JWKS Endpoint**: https://localhost:8443/realms/testrealm/protocol/openid-connect/certs

## トラブルシューティング

### ユーザーが作成されない

ログを確認してください：

```bash
docker logs template-cicd-keycloak
```

### 既存のデータをクリアして再セットアップ

```bash
docker compose down -v
docker compose up -d
```

### スクリプトを手動で再実行

```bash
docker exec -it template-cicd-keycloak bash /opt/keycloak/bin/setup-realm.sh
```

## セキュリティに関する注意

⚠️ **本番環境での使用について**:

- デフォルトのパスワードは必ず変更してください
- 自己署名証明書を適切な証明書に置き換えてください
- クライアントシークレットを強力なものに変更してください
- 不要なユーザーアカウントは削除してください
