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

#### 環境構成

- **開発環境**: ローカル（cargo run / npm run dev）
- **ステージング環境**: Docker Compose または Minikube
- **本番環境**: AWS (EKS または ECS Fargate) - Single Region
- **災対環境**: AWS Multi-Region (Primary: Tokyo / Secondary: Osaka)

#### 前提条件

- AWS CLI 設定済み
- Terraform 1.6+（インフラ構築用）
- kubectl（EKS 使用時）

#### Single Region デプロイ

##### EKS へのデプロイ

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

##### ECS Fargate へのデプロイ

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

#### Multi-Region Disaster Recovery デプロイ

災害対策用のマルチリージョン構成を自動的にデプロイします。

```bash
# 1. 両リージョンのインフラを構築
make multi-region-init    # Terraform初期化
make multi-region-plan    # 変更プレビュー
make multi-region-apply   # 適用（Primary + Secondary同時）

# 2. アプリケーションを両リージョンにデプロイ
make multi-region-deploy-app

# 3. ステータス確認
make multi-region-status
```

マルチリージョン構成の詳細は [infra/terraform/multi-region/README.md](infra/terraform/multi-region/README.md) を参照。

##### マルチリージョンの特徴

- **Aurora Global Database**: Primary→Secondary への自動レプリケーション（RPO < 1 秒）
- **ECR Replication**: コンテナイメージの自動複製
- **Route 53 Failover**: Primary 障害時の自動 DNS 切り替え（RTO < 2 分）
- **ヘルスチェック**: 30 秒間隔での死活監視

#### GitHub Actions 自動デプロイ

```bash
# GitHub Secretsを設定（必須）
# Settings → Secrets → Actions
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY

# mainブランチへのプッシュで自動デプロイ
git push origin main
```

詳細は [GITHUB_SECRETS.md](GITHUB_SECRETS.md) を参照。

#### AWS 環境変数

```bash
# Single Region
export AWS_REGION=ap-northeast-1
export DEPLOY_TARGET=eks  # または ecs
export IMAGE_TAG=v1.0.0   # 省略時はgit commit hash

# Multi-Region
export AWS_REGION_PRIMARY=ap-northeast-1
export AWS_REGION_SECONDARY=ap-northeast-3
```

詳細は [infra/terraform/README.md](infra/terraform/README.md) を参照。

#### クリーンアップ

```bash
# Minikube
make k8s-clean

# AWS Single Region
make prod-clean DEPLOY_TARGET=eks
# または
make prod-clean DEPLOY_TARGET=ecs

# AWS Multi-Region (全削除)
make multi-region-destroy
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

### GitHub Actions

main ブランチへのプッシュで自動実行:

1. **Pull Request**: テスト実行、Lint チェック
2. **main ブランチマージ**: ビルド、テスト、ステージング環境へデプロイ（オプション）
3. **Multi-Region Production**: 両リージョンへの同時デプロイ

#### Multi-Region CI/CD フロー

```mermaid
graph LR
    A[Push to main] --> B[Run Tests]
    B --> C[Build Images]
    C --> D[Push to ECR Primary]
    D --> E[ECR Replication]
    E --> F[Terraform Apply]
    F --> G[Deploy to Primary]
    F --> H[Deploy to Secondary]
    G --> I[Health Check]
    H --> I
    I --> J[Route53 Update]
```

詳細は `.github/workflows/deploy-multi-region.yml` を参照。

### ローカルでの CI/CD テスト

```bash
# Act を使ってローカルでGitHub Actionsをテスト
act -j test
```

## ディレクトリ構造

```
template-cicd/
├── backend/                  # Rustバックエンド
├── frontend/                 # Reactフロントエンド
├── infra/                    # インフラ設定
│   ├── docker/               # Dockerfile群
│   ├── kubernetes/           # K8sマニフェスト
│   ├── keycloak/             # Keycloak設定
│   └── terraform/            # Infrastructure as Code
│       ├── eks/              # EKS Single Region
│       ├── ecs/              # ECS Single Region
│       ├── multi-region/     # Multi-Region DR
│       └── modules/          # 共通Terraformモジュール
├── .github/
│   └── workflows/            # CI/CD定義
│       └── deploy-multi-region.yml  # マルチリージョンデプロイ
└── .vscode/                  # VS Code設定
```

## アーキテクチャ

### Multi-Region Disaster Recovery

```
┌─────────────────────────────────────────────────────────────┐
│                      Route 53 (Failover)                     │
│                    Health Check: Primary                     │
└───────────────────┬─────────────────┬───────────────────────┘
                    │                 │
        ┌───────────▼──────┐  ┌──────▼───────────┐
        │  Primary Region  │  │ Secondary Region │
        │  ap-northeast-1  │  │  ap-northeast-3  │
        ├──────────────────┤  ├──────────────────┤
        │ EKS Cluster      │  │ EKS Cluster      │
        │ - Backend Pods   │  │ - Backend Pods   │
        │ - Frontend Pods  │  │ - Frontend Pods  │
        │ ALB (HTTPS)      │  │ ALB (HTTPS)      │
        │                  │  │                  │
        │ Aurora Primary   │◄─┤ Aurora Secondary │
        │ (Read/Write)     │  │ (Read-Only)      │
        └──────────────────┘  └──────────────────┘
                │                       ▲
                └───── Global DB ───────┘
                    (< 1 sec RPO)
```

### コスト最適化

| 環境               | 月額コスト (USD)        |
| ------------------ | ----------------------- |
| 開発環境           | $0 (ローカル)           |
| ステージング       | $0-50 (Docker/Minikube) |
| 本番 Single Region | $150-200                |
| 本番 Multi-Region  | $396-481                |

## ライセンス

MIT
