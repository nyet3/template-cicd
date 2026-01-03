# AWS Infrastructure with Terraform

このディレクトリには、本番環境用の AWS インフラを Terraform で管理するための設定が含まれています。

## 構成オプション

### 1. EKS (Elastic Kubernetes Service)

- マネージド Kubernetes クラスター
- 既存の Kubernetes manifests をそのまま使用可能
- Auto Scaling Group 対応
- VPC, ALB, ACM 証明書の自動セットアップ

### 2. ECS + Fargate

- サーバーレスコンテナ実行環境
- タスク定義ベースのシンプルな構成
- ALB + Target Group
- CloudWatch Logs 統合

## 前提条件

```bash
# Terraform インストール
brew install terraform  # macOS
# または
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# AWS CLI 設定
aws configure
```

## クイックスタート

### EKS へのデプロイ

```bash
cd infra/terraform/eks
terraform init
terraform plan
terraform apply

# デプロイ
make prod-deploy DEPLOY_TARGET=eks
```

### ECS Fargate へのデプロイ

```bash
cd infra/terraform/ecs
terraform init
terraform plan
terraform apply

# デプロイ
make prod-deploy DEPLOY_TARGET=ecs
```

## Makefile コマンド

### AWS 共通

```bash
# ECRログイン
make aws-login

# イメージビルド＆プッシュ
make aws-ecr-push IMAGE_TAG=v1.0.0
```

### EKS

```bash
# デプロイ
make aws-eks-deploy

# ステータス確認
make aws-eks-status

# クリーンアップ
make aws-eks-clean
```

### ECS

```bash
# デプロイ
make aws-ecs-deploy

# ステータス確認
make aws-ecs-status

# クリーンアップ
make aws-ecs-clean
```

### 統一コマンド

```bash
# EKSにデプロイ
make prod-deploy DEPLOY_TARGET=eks

# ECSにデプロイ
make prod-deploy DEPLOY_TARGET=ecs

# ステータス確認
make prod-status DEPLOY_TARGET=eks

# クリーンアップ
make prod-clean DEPLOY_TARGET=ecs
```

## 環境変数

```bash
# AWS設定
export AWS_REGION=ap-northeast-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# ECR設定
export ECR_REGISTRY=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
export ECR_REPO_BACKEND=template-cicd/backend
export ECR_REPO_FRONTEND=template-cicd/frontend

# EKS設定
export EKS_CLUSTER_NAME=template-cicd-cluster
export EKS_NAMESPACE=template-cicd

# ECS設定
export ECS_CLUSTER_NAME=template-cicd-cluster
export ECS_SERVICE_BACKEND=template-cicd-backend
export ECS_SERVICE_FRONTEND=template-cicd-frontend

# イメージタグ
export IMAGE_TAG=$(git rev-parse --short HEAD)
```

## ディレクトリ構造

```
infra/terraform/
├── README.md           # このファイル
├── eks/                # EKS構成
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
└── ecs/                # ECS構成
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── versions.tf
```

## データベース

### Aurora PostgreSQL Serverless v2

本番環境では Amazon Aurora PostgreSQL Serverless v2 を使用します。

#### 特徴

- **自動スケーリング**: 0.5 ACU ~ 2 ACU (1 ACU = 2GB RAM)
- **高可用性**: Multi-AZ 構成 (Writer + Reader)
- **自動バックアップ**: 7 日間保持
- **Secrets Manager 統合**: DB 接続情報を安全に管理

#### 接続情報の取得

```bash
# Terraformから出力
terraform output database_url

# Secrets Managerから取得
aws secretsmanager get-secret-value \
  --secret-id template-cicd-aurora-credentials \
  --query SecretString \
  --output text | jq -r .DATABASE_URL
```

#### Aurora 設定のカスタマイズ

`variables.tf`で以下の変数を変更できます：

```hcl
database_name            = "templatecicd"         # データベース名
aurora_engine_version    = "15.4"                  # PostgreSQLバージョン
aurora_min_capacity      = 0.5                     # 最小ACU
aurora_max_capacity      = 2                       # 最大ACU
aurora_instance_count    = 2                       # インスタンス数 (Writer + Reader)
backup_retention_period  = 7                       # バックアップ保持期間
```

#### Security Group

Aurora DB には以下のアクセスが許可されています：

- **EKS 構成**: EKS クラスターのノードセキュリティグループから 5432 ポート
- **ECS 構成**: ECS タスクセキュリティグループから 5432 ポート

## コスト見積もり

### EKS (最小構成)

- EKS Control Plane: $0.10/時間 ($72/月)
- EC2 t3.medium × 2: ~$60/月
- ALB: ~$20/月
- Aurora Serverless v2 (0.5-2 ACU): ~$40-80/月
- **合計: ~$190-280/月**

### ECS Fargate (最小構成)

- Fargate vCPU: 0.25 × 3 タスク × $0.04048/時間
- Fargate Memory: 0.5GB × 3 タスク × $0.004445/GB/時間
- ALB: ~$20/月
- Aurora Serverless v2 (0.5-2 ACU): ~$40-80/月
- **合計: ~$90-160/月**

## トラブルシューティング

### ECR ログインエラー

```bash
# AWS CLIの認証情報を確認
aws sts get-caller-identity

# ECRリポジトリを作成
aws ecr create-repository --repository-name template-cicd/backend
aws ecr create-repository --repository-name template-cicd/frontend
```

### EKS クラスタへのアクセスエラー

```bash
# kubeconfigを更新
aws eks update-kubeconfig --region ap-northeast-1 --name template-cicd-cluster

# 権限を確認
kubectl auth can-i '*' '*'
```

### ECS タスクが起動しない

```bash
# タスク定義を確認
aws ecs describe-task-definition --task-definition template-cicd-backend

# タスクログを確認
aws logs tail /ecs/template-cicd-backend --follow
```

## セキュリティ考慮事項

1. **IAM ロール**: 最小権限の原則に従う
2. **Secrets Manager**: DB 接続情報などの機密情報を保存
3. **ACM 証明書**: HTTPS 通信を有効化
4. **Security Groups**: 必要最小限のポート開放
5. **VPC**: プライベートサブネットでコンテナを実行

## 次のステップ

1. Terraform state を S3 で管理
2. CI/CD (GitHub Actions) との統合
3. Monitoring (CloudWatch, Prometheus)
4. Auto Scaling 設定
5. Multi-AZ 構成
