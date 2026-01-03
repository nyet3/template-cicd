# クイックスタートガイド

このガイドでは、template-cicd プロジェクトの開発環境のセットアップ方法を説明します。

## 前提条件

- Rust 1.75 以上
- Node.js 20 以上
- Docker & Docker Compose
- VS Code（推奨）

## セットアップ手順

### 1. リポジトリのクローン

```bash
git clone <repository-url>
cd template-cicd
```

### 2. バックエンドのセットアップ

```bash
cd backend
cp .env.example .env
cargo build
```

### 3. フロントエンドのセットアップ

```bash
cd ../frontend
npm install
```

### 4. VS Code での開発

VS Code で `template-cicd` フォルダを開き、推奨拡張機能をインストールします。

#### デバッグ実行（推奨）

1. VS Code で F5 キーを押す
2. バックエンド（Rust）とフロントエンド（React）が同時に起動します
3. ブラウザで http://localhost:5173 にアクセス

#### 手動実行

バックエンド:

```bash
cd backend
cargo run
```

フロントエンド（別のターミナル）:

```bash
cd frontend
npm run dev
```

### 5. 動作確認

- フロントエンド: http://localhost:5173
- バックエンド API: http://localhost:8080/health
- 認証情報: 開発環境ではダミー認証が有効

## CI/CD 事前チェック

コードをプッシュする前に、GitHub Actions CI/CD と同じチェックをローカルで実行できます。

### すべてのチェックを実行

```bash
make ci-check
```

または

```bash
./scripts/ci-check.sh
```

### 個別チェック

```bash
# バックエンドのみ (テスト + Clippy)
make ci-backend

# フロントエンドのみ (Lint + テスト + ビルド)
make ci-frontend
```

### チェック内容

- ✅ **Backend Tests**: `cargo test --verbose`
- ✅ **Backend Clippy**: `cargo clippy -- -D warnings`
- ✅ **Frontend Lint**: `npm run lint`
- ✅ **Frontend Tests**: `npm test -- --run`
- ✅ **Frontend Build**: `npm run build`

すべてのチェックが通れば、CI/CD も成功します。

## Docker 環境でのセットアップ（推奨）

### 1. 証明書の生成

初回セットアップ時に、HTTPS 通信用の自己署名証明書を生成します：

```bash
# 全ての証明書を生成（Docker Compose + Kubernetes）
make certs

# Docker Compose用のみ
make certs-docker
```

### 2. Docker サービスの起動

```bash
docker compose up -d
```

このコマンドで以下が自動的にセットアップされます：

- PostgreSQL データベース
- Keycloak 認証サーバー（HTTPS ポート: 8443）
- バックエンド API サーバー（ポート: 8080）
- フロントエンド Web サーバー（ポート: 5173）

### 3. Keycloak のセットアップ（初回のみ）

サービス起動後、Keycloak のレアルムとユーザーを設定します：

```bash
make keycloak-setup
```

このコマンドは以下を自動実行します：

- レアルム（testrealm）の作成
- サンプルユーザーとロールの作成
- グループ（Administrators, Developers, Operations, Viewers, Beginers）の作成
- バックエンド/フロントエンドクライアントの設定

### 4. アクセス

- **フロントエンド**: http://localhost:5173
- **バックエンド API**: http://localhost:8080
- **Keycloak Admin**: https://localhost:8443/admin/
  - ユーザー名: `admin`
  - パスワード: `admin`

### 5. サンプルユーザー

Keycloak には以下のサンプルユーザーが自動作成されます：

| ユーザー名 | メールアドレス       | パスワード  | グループ       | ロール（グループから継承） | 用途               |
| ---------- | -------------------- | ----------- | -------------- | -------------------------- | ------------------ |
| admin      | admin@example.com    | admin123    | Administrators | admin, manager             | 管理者テスト       |
| testuser   | test@example.com     | testpass123 | Developers     | user, editor               | 開発者テスト       |
| manager    | manager@example.com  | manager123  | Managers       | manager, user              | マネージャーテスト |
| viewer     | viewer@example.com   | viewer123   | Viewers        | viewer                     | 閲覧者テスト       |
| beginner   | beginner@example.com | beginner123 | Beginners      | beginner                   | 初心者テスト       |

### 6. 動作確認

1. http://localhost:5173 にアクセス
2. 「ログイン」ボタンをクリック
3. 上記のいずれかのユーザーでログイン
4. ユーザー情報とユーザー一覧が表示されることを確認

### 7. サービスの停止と再起動

```bash
# サービスを停止
docker compose down

# データを含めて完全にクリーンアップ
docker compose down -v

# 再起動
docker compose up -d
```

### 8. ログの確認

```bash
# 全サービスのログを表示
docker compose logs -f

# 特定のサービスのログを表示
docker compose logs -f keycloak
docker compose logs -f backend
docker compose logs -f frontend

# Keycloakのログを表示（環境自動検出）
make keycloak-logs
```

### 9. Keycloak のトラブルシューティング

#### ユーザーが作成されていない場合

```bash
# Keycloakのセットアップを再実行
make keycloak-setup-docker

# ログを確認
make keycloak-logs
```

#### データをリセットして再セットアップ

```bash
# 全データを削除して再構築（確認プロンプトあり）
make keycloak-reset
```

#### クライアント設定の更新

```bash
# フロントエンドクライアントのリダイレクトURIを更新
make keycloak-client-update
```

## テスト環境（レガシー）

Docker Compose を使用してテスト環境を起動:

```bash
docker-compose -f docker-compose.test.yml up --build
```

これにより以下が起動します:

- PostgreSQL データベース
- Keycloak 認証サーバー (http://localhost:8180)
- バックエンド API
- フロントエンド

### Keycloak 管理コンソール

- URL: http://localhost:8180
- Username: admin
- Password: admin

## 本番環境デプロイ

### Kubernetes へのデプロイ

#### ローカル開発環境（minikube）

1. 証明書を生成して Kubernetes シークレットを作成:

```bash
make certs-k8s
```

このコマンドは以下を実行します：

- Frontend/Keycloak 用の自己署名証明書を生成
- Kubernetes シークレット（frontend-tls, keycloak-tls）を作成

2. Docker イメージをビルド:

```bash
eval $(minikube docker-env)
docker build -t backend:latest -f infra/docker/backend.Dockerfile backend/
docker build -t frontend:latest -f infra/docker/frontend.Dockerfile frontend/
```

3. Namespace を作成:

```bash
kubectl apply -f infra/kubernetes/namespace.yaml
```

4. Secrets を設定:

```bash
kubectl apply -f infra/kubernetes/secrets.yaml
```

5. アプリケーションをデプロイ:

```bash
# または一括デプロイ
make k8s-deploy
```

6. Keycloak のセットアップ（初回のみ）:

```bash
make keycloak-setup-k8s
```

7. 稼働確認:

```bash
# Pod の状態確認
kubectl get pods -n template-cicd

# ログ確認
kubectl logs -n template-cicd -l app=backend --tail=20
kubectl logs -n template-cicd -l app=frontend --tail=20

# ポートフォワードでアクセス
kubectl port-forward -n template-cicd svc/frontend 5173:80
kubectl port-forward -n template-cicd svc/backend 8080:8080
```

ブラウザで http://localhost:5173 にアクセス

### GitHub Actions 経由のデプロイ

1. GitHub Secrets を設定:

   - `REGISTRY_URL`: コンテナレジストリ URL
   - `REGISTRY_USERNAME`: レジストリユーザー名
   - `REGISTRY_PASSWORD`: レジストリパスワード
   - `KUBECONFIG_STAGING`: ステージング環境の kubeconfig
   - `KUBECONFIG_PRODUCTION`: 本番環境の kubeconfig

2. main ブランチへマージ → ステージング環境へ自動デプロイ
3. タグをプッシュ（例: v1.0.0）→ 本番環境へデプロイ

```bash
git tag v1.0.0
git push origin v1.0.0
```

### Kubernetes へのアクセス

Kubernetes 環境のサービスにアクセスするには、ポートフォワーディングを設定します：

#### 自動化された方法（推奨）

```bash
# Makefileを使用
make k8s-port-forward

# または直接スクリプトを実行
./infra/kubernetes/port-forward.sh

# 停止する場合
make k8s-stop-port-forward
```

#### VS Code タスクを使用

1. `Ctrl+Shift+P` → "Tasks: Run Task"
2. "K8s: Port Forward Services" を選択
3. ポートフォワーディングが開始されます

停止する場合:

1. `Ctrl+Shift+P` → "Tasks: Run Task"
2. "K8s: Stop Port Forward" を選択

#### アクセス URL

- **フロントエンド**: https://localhost:3000
- **バックエンド**: http://localhost:8080
- **Keycloak**: https://localhost:8443

⚠️ 自己署名証明書を使用しているため、ブラウザで警告が表示されます。

#### 手動でポートフォワーディング

```bash
# Frontend
kubectl port-forward -n template-cicd service/frontend 3000:443

# Backend
kubectl port-forward -n template-cicd service/backend 8080:8080

# Keycloak
kubectl port-forward -n template-cicd service/keycloak 8443:8443
```

## トラブルシューティング

### バックエンドがビルドできない

```bash
cd backend
cargo clean
cargo build
```

### フロントエンドの型エラー

```bash
cd frontend
rm -rf node_modules package-lock.json
npm install
```

### データベース接続エラー

開発環境では SQLite を使用しています。`backend/.env` で `DATABASE_URL` が正しく設定されているか確認してください。

## 便利な Make コマンド一覧

### 開発・ビルド

```bash
# すべてのテストを実行
make test

# すべてをビルド
make build

# クリーンアップ
make clean
```

### 証明書管理

```bash
# 全ての証明書を生成（Docker + K8s）
make certs

# Kubernetes用証明書のみ
make certs-k8s

# Docker Compose用証明書のみ
make certs-docker

# 証明書を削除
make certs-clean
```

### Docker Compose

```bash
# Docker イメージをビルド
make docker-build

# テスト環境を起動
make docker-test
```

### Kubernetes

```bash
# Kubernetes にデプロイ
make k8s-deploy

# ポートフォワーディング開始
make k8s-port-forward

# ポートフォワーディング停止
make k8s-stop-port-forward
```

### Keycloak 管理

```bash
# Keycloakセットアップ（環境自動検出）
make keycloak-setup

# Docker Compose環境でセットアップ
make keycloak-setup-docker

# Kubernetes環境でセットアップ
make keycloak-setup-k8s

# ログ表示
make keycloak-logs

# データリセット（確認あり）
make keycloak-reset

# フロントエンドクライアント設定更新
make keycloak-client-update
```

### 完全なヘルプを表示

```bash
make help
```

## 次のステップ

- [README.md](README.md) - プロジェクト全体の概要
- [backend/README.md](backend/README.md) - バックエンド詳細
- [frontend/README.md](frontend/README.md) - フロントエンド詳細
- [infra/keycloak/README.md](infra/keycloak/README.md) - Keycloak 設定
