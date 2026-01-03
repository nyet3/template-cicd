# AWS Infrastructure with Terraform

このディレクトリには、本番環境用のAWSインフラをTerraformで管理するための設定が含まれています。

## 構成オプション

### 1. EKS (Elastic Kubernetes Service)
- マネージドKubernetesクラスター
- 既存のKubernetes manifestsをそのまま使用可能
- Auto Scaling Group対応
- VPC, ALB, ACM証明書の自動セットアップ

### 2. ECS + Fargate
- サーバーレスコンテナ実行環境
- タスク定義ベースのシンプルな構成
- ALB + Target Group
- CloudWatch Logs統合

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

### EKSへのデプロイ

```bash
cd infra/terraform/eks
terraform init
terraform plan
terraform apply

# デプロイ
make prod-deploy DEPLOY_TARGET=eks
```

### ECS Fargateへのデプロイ

```bash
cd infra/terraform/ecs
terraform init
terraform plan
terraform apply

# デプロイ
make prod-deploy DEPLOY_TARGET=ecs
```

## Makefileコマンド

### AWS共通

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

## コスト見積もり

### EKS (最小構成)
- EKS Control Plane: $0.10/時間 ($72/月)
- EC2 t3.medium × 2: ~$60/月
- ALB: ~$20/月
- **合計: ~$150-200/月**

### ECS Fargate (最小構成)
- Fargate vCPU: 0.25 × 3タスク × $0.04048/時間
- Fargate Memory: 0.5GB × 3タスク × $0.004445/GB/時間
- ALB: ~$20/月
- **合計: ~$50-80/月**

## トラブルシューティング

### ECRログインエラー

```bash
# AWS CLIの認証情報を確認
aws sts get-caller-identity

# ECRリポジトリを作成
aws ecr create-repository --repository-name template-cicd/backend
aws ecr create-repository --repository-name template-cicd/frontend
```

### EKSクラスタへのアクセスエラー

```bash
# kubeconfigを更新
aws eks update-kubeconfig --region ap-northeast-1 --name template-cicd-cluster

# 権限を確認
kubectl auth can-i '*' '*'
```

### ECSタスクが起動しない

```bash
# タスク定義を確認
aws ecs describe-task-definition --task-definition template-cicd-backend

# タスクログを確認
aws logs tail /ecs/template-cicd-backend --follow
```

## セキュリティ考慮事項

1. **IAMロール**: 最小権限の原則に従う
2. **Secrets Manager**: DB接続情報などの機密情報を保存
3. **ACM証明書**: HTTPS通信を有効化
4. **Security Groups**: 必要最小限のポート開放
5. **VPC**: プライベートサブネットでコンテナを実行

## 次のステップ

1. Terraform stateをS3で管理
2. CI/CD (GitHub Actions) との統合
3. Monitoring (CloudWatch, Prometheus)
4. Auto Scaling設定
5. Multi-AZ構成
