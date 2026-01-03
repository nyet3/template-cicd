# Multi-Region Disaster Recovery Setup

このドキュメントでは、マルチリージョン DR（Disaster Recovery）環境のセットアップ方法を説明します。

## アーキテクチャ概要

### リージョン構成

- **Primary Region**: `ap-northeast-1` (東京)
- **Secondary Region**: `ap-northeast-3` (大阪)

### コンポーネント

#### 各リージョンにデプロイされるもの

- EKS Cluster (Kubernetes 1.28)
- VPC (プライベート/パブリックサブネット × 3 AZ)
- Application Load Balancer (ALB)
- EKS Node Group (t3.medium × 2-4)
- Aurora PostgreSQL Serverless v2

#### グローバルリソース

- **Aurora Global Database**: プライマリ → セカンダリへの自動レプリケーション
- **ECR Replication**: コンテナイメージの自動複製
- **Route 53 Health Checks**: 各リージョンの死活監視
- **Route 53 Failover**: プライマリ障害時の DNS 自動切り替え

## セットアップ手順

### 1. 前提条件

```bash
# 必要なツール
- Terraform >= 1.6
- AWS CLI >= 2.0
- kubectl >= 1.28
- Docker

# AWS認証情報の設定
aws configure
```

### 2. Terraform でインフラ構築

```bash
# 初期化
make multi-region-init

# プラン確認
make multi-region-plan

# デプロイ（両リージョンに同時展開）
make multi-region-apply
```

このコマンドで以下が自動的にデプロイされます：

- 両リージョンの VPC、EKS、ALB
- Aurora Global Database (Primary + Secondary)
- ECR リポジトリとレプリケーション設定
- Route 53 ヘルスチェック
- Secrets Manager (DB 接続情報)

### 3. コンテナイメージのビルドとプッシュ

```bash
# ECRにログイン
make aws-login

# イメージビルド & プッシュ (プライマリリージョンに自動複製)
make aws-ecr-push IMAGE_TAG=v1.0.0
```

ECR Replication により、プライマリリージョンにプッシュしたイメージが自動的にセカンダリリージョンに複製されます。

### 4. アプリケーションのデプロイ

```bash
# 両リージョンに同時デプロイ
make multi-region-deploy-app
```

または、GitHub Actions を使用した自動デプロイ：

```bash
# mainブランチへのプッシュで自動デプロイ
git push origin main
```

### 5. ステータス確認

```bash
# 両リージョンの状態を確認
make multi-region-status
```

出力例：

```
🌍 Multi-Region Status
==============================================

📍 Primary Region: ap-northeast-1
--------------------------------------------
EKS Clusters:
- template-cicd-cluster-apne1: ACTIVE
- Endpoint: https://xxxxx.eks.ap-northeast-1.amazonaws.com

Load Balancers:
- template-cicd-alb-apne1: active
- DNS: xxx.ap-northeast-1.elb.amazonaws.com

Aurora Clusters:
- template-cicd-aurora-primary: available
- Endpoint: xxx.cluster-xxx.ap-northeast-1.rds.amazonaws.com

📍 Secondary Region: ap-northeast-3
--------------------------------------------
(同様の情報が表示されます)
```

## CI/CD 自動デプロイ

### GitHub Actions 設定

必要な Secrets を設定：

```bash
# GitHub Secretsに設定
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

詳細は [GITHUB_SECRETS.md](GITHUB_SECRETS.md) を参照してください。

### デプロイフロー

1. **main ブランチへのプッシュ**で自動的にトリガー
2. **テスト実行** (backend + frontend)
3. **イメージビルド & ECR プッシュ** (Primary → Secondary 自動複製)
4. **Terraform Plan & Apply** (インフラ更新)
5. **アプリケーションデプロイ** (両リージョン並行)
6. **ヘルスチェック** (デプロイ後の動作確認)

### 手動デプロイ

```bash
# GitHub ActionsのUIから手動実行
Actions → Multi-Region Production Deployment → Run workflow

# オプション:
# - deploy_target: both/primary/secondary
# - skip_tests: true/false
```

## フェイルオーバー

### 自動フェイルオーバー (Route 53)

Route 53 のヘルスチェックにより、プライマリリージョンの障害を検知すると自動的にセカンダリリージョンへ DNS フェイルオーバーします。

- **ヘルスチェック間隔**: 30 秒
- **障害閾値**: 3 回連続失敗
- **フェイルオーバー時間**: 約 1-2 分

### 手動フェイルオーバー

プライマリリージョンで障害が発生した場合：

```bash
# Route 53でセカンダリをプライマリに昇格
# (Terraformで管理する場合は main.tf のコメント解除が必要)
```

### Aurora Global Database のフェイルオーバー

```bash
# セカンダリAuroraクラスタをプライマリに昇格
aws rds failover-global-cluster \
  --global-cluster-identifier template-cicd-cluster-global \
  --target-db-cluster-identifier template-cicd-aurora-secondary \
  --region ap-northeast-3

# アプリケーションのDB接続先を更新
kubectl set env deployment/backend \
  DATABASE_URL="postgresql://..." \
  -n template-cicd
```

## コスト見積もり

### 両リージョン合計 (最小構成)

| サービス                      | 月額コスト (USD) |
| ----------------------------- | ---------------- |
| EKS Control Plane × 2         | $144             |
| EC2 t3.medium × 4 (2/region)  | $124             |
| ALB × 2                       | $42              |
| Aurora Serverless v2 (Global) | $85-170          |
| Route 53 Health Checks        | $1               |
| **合計**                      | **$396-481**     |

> 注: 大阪リージョンは東京と同価格帯です。

### コスト削減オプション

- Spot Instances 使用: 最大 70%削減
- Aurora ACU 最小化: 0.5 ACU 固定で約$40/月
- NAT Gateway 統合: シングル NAT 使用で約$32/月削減

## トラブルシューティング

### プライマリリージョンに接続できない

```bash
# セカンダリリージョンのステータス確認
aws eks describe-cluster \
  --region ap-northeast-3 \
  --name template-cicd-cluster-oska

# kubeconfigをセカンダリに切り替え
aws eks update-kubeconfig \
  --region ap-northeast-3 \
  --name template-cicd-cluster-oska
```

### ECR イメージが複製されない

```bash
# レプリケーション設定確認
aws ecr describe-registry \
  --region ap-northeast-1 \
  --query 'replicationConfiguration'

# 手動で複製
aws ecr replicate-image \
  --source-region ap-northeast-1 \
  --destination-region ap-northeast-3 \
  --repository-name template-cicd/backend \
  --image-tag latest
```

### Aurora レプリケーション遅延

```bash
# レプリケーション状態確認
aws rds describe-global-clusters \
  --global-cluster-identifier template-cicd-cluster-global \
  --query 'GlobalClusters[0].GlobalClusterMembers'
```

## クリーンアップ

### アプリケーションのみ削除

```bash
# 各リージョンのKubernetesリソース削除
kubectl delete namespace template-cicd
```

### 全インフラ削除

```bash
# ⚠️ 警告: 両リージョンのすべてのリソースが削除されます
make multi-region-destroy
```

## 参考資料

- [Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html)
- [Route 53 Health Checks](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks-creating.html)
- [ECR Replication](https://docs.aws.amazon.com/AmazonECR/latest/userguide/replication.html)
- [EKS Multi-Region](https://aws.amazon.com/blogs/containers/multi-region-application-on-eks/)
