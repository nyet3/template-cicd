# Template CICD

React + Rust + Kubernetes + GitHub Actions CI/CD テンプレートプロジェクト

## 技術スタック

### フロントエンド

- React + TypeScript + Vite
- OIDC 認証（Keycloak 連携）

### バックエンド

- Rust (Actix-web)
- 環境別データベース:
  - 開発環境: SQLite
  - テスト環境: PostgreSQL
  - 本番環境・災対環境: AWS RDS (PostgreSQL)
- OIDC 認証（Keycloak 連携、開発環境はダミー認証）

### インフラ

- Docker & Docker Compose
- Kubernetes
- GitHub Actions CI/CD
- Keycloak (認証サーバー)

## クイックスタート

### 開発環境

#### 必要な環境

- Rust 1.75+
- Node.js 20+
- Docker & Docker Compose
- VS Code (推奨)

#### セットアップ

1. 依存関係のインストール:

```bash
# バックエンド
cd backend
cargo build

# フロントエンド
cd ../frontend
npm install
```

2. VS Code でデバッグ:

- F5 キーを押すとバックエンド(LLDB)とフロントエンド(npm run dev)が同時に起動します

#### 手動起動

```bash
# バックエンド
cd backend
cargo run

# フロントエンド (別ターミナル)
cd frontend
npm run dev
```

### ステージング環境

#### Docker Compose

```bash
docker-compose -f docker-compose.test.yml up --build
```

#### Minikube / Kubernetes

```bash
minikube start
make k8s-deploy
```

これだけで以下が自動的に実行されます：

- TLS 証明書の生成
- Docker イメージのビルド（Minikube 環境内）
- Kubernetes リソースのデプロイ
- Keycloak realm のインポート
- Port-forward の開始

アクセス URL：

- **フロントエンド**: https://localhost:3000
- **バックエンド**: http://localhost:8080
- **Keycloak**: https://localhost:8443

テスト用認証情報：

- Username: `testuser`
- Password: `testpass123`

⚠️ ブラウザで自己署名証明書の警告が表示されますが、問題ありません。

### 本番環境 (AWS)

#### 前提条件

- AWS CLI設定済み
- Terraform 1.0+（インフラ構築用）
- kubectl（EKS使用時）

#### EKSへのデプロイ

```bash
# 1. インフラをTerraformで構築
cd infra/terraform/eks
terraform init
terraform apply

# 2. アプリケーションをデプロイ
cd ../../..
make prod-deploy DEPLOY_TARGET=eks

# ステータス確認
make prod-status DEPLOY_TARGET=eks
```

#### ECS Fargateへのデプロイ

```bash
# 1. インフラをTerraformで構築
cd infra/terraform/ecs
terraform init
terraform apply

# 2. アプリケーションをデプロイ
cd ../../..
make prod-deploy DEPLOY_TARGET=ecs

# ステータス確認
make prod-status DEPLOY_TARGET=ecs
```

#### AWS環境変数

```bash
export AWS_REGION=ap-northeast-1
export DEPLOY_TARGET=eks  # または ecs
export IMAGE_TAG=v1.0.0   # 省略時はgit commit hash
```

詳細は [infra/terraform/README.md](infra/terraform/README.md) を参照。

#### クリーンアップ

```bash
# Minikube
make k8s-clean

# AWS
make prod-clean DEPLOY_TARGET=eks
# または
make prod-clean DEPLOY_TARGET=ecs
```

## 環境変数

### バックエンド

開発環境 (`.env`):

```env
DATABASE_URL=sqlite://./dev.db
ENVIRONMENT=development
```

ステージング環境:

```env
DATABASE_URL=postgresql://user:password@postgres:5432/testdb
ENVIRONMENT=test
OIDC_ISSUER_URL=http://keycloak:8080/realms/myrealm
OIDC_CLIENT_ID=backend-client
```

本番環境 (AWS Secrets Manager):

- DATABASE_URL: AWS RDS 接続文字列
- OIDC_ISSUER_URL: Keycloak URL
- OIDC_CLIENT_ID: クライアント ID

### フロントエンド

開発環境 (`.env.development`):

```env
VITE_API_URL=http://localhost:8080
VITE_AUTH_ENABLED=false
```

本番環境 (`.env.production`):

```env
VITE_API_URL=https://api.example.com
VITE_AUTH_ENABLED=true
VITE_OIDC_AUTHORITY=https://keycloak.example.com/realms/myrealm
VITE_OIDC_CLIENT_ID=frontend-client
```

## CI/CD

GitHub Actions が以下を自動実行:

1. **Pull Request**: テスト実行、Lint チェック
2. **main ブランチマージ**: ビルド、テスト、ステージング環境へデプロイ
3. **タグプッシュ**: 本番環境へデプロイ

詳細は `.github/workflows/` を参照。

## ディレクトリ構造

```
template-cicd/
├── backend/           # Rustバックエンド
├── frontend/          # Reactフロントエンド
├── infra/             # インフラ設定
│   ├── docker/        # Dockerfile群
│   ├── kubernetes/    # K8sマニフェスト
│   └── keycloak/      # Keycloak設定
├── .github/workflows/ # CI/CD定義
└── .vscode/           # VS Code設定
```

## ライセンス

MIT
