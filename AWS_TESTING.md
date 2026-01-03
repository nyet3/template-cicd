# AWS 環境テスト手順書

このドキュメントでは、AWS 上にデプロイしたアプリケーションの動作確認手順を説明します。

## 目次

1. [前提条件](#前提条件)
2. [Single Region テスト（EKS）](#single-region-テストeks)
3. [Single Region テスト（ECS）](#single-region-テストecs)
4. [Multi-Region テスト](#multi-region-テスト)
5. [機能テスト](#機能テスト)
6. [フェイルオーバーテスト](#フェイルオーバーテスト)
7. [パフォーマンステスト](#パフォーマンステスト)
8. [クリーンアップ](#クリーンアップ)

---

## 前提条件

### 必要なツール

```bash
# バージョン確認
aws --version        # >= 2.0
terraform --version  # >= 1.6
kubectl version      # >= 1.28
curl --version
jq --version

# インストールが必要な場合
# macOS
brew install awscli terraform kubectl jq

# Linux
sudo apt-get install awscli jq
```

### AWS 認証情報の設定

> **注意**: GitHub Actions で AWS デプロイを有効にするには、`AWS_ACCESS_KEY_ID`と`AWS_SECRET_ACCESS_KEY`を GitHub Secrets に設定する必要があります。設定方法は[GITHUB_SECRETS.md](./GITHUB_SECRETS.md)を参照してください。

```bash
# AWS CLIの設定
aws configure
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region name: ap-northeast-1
# Default output format: json

# 認証確認
aws sts get-caller-identity

# 出力例:
# {
#     "UserId": "AIDAXXXXXXXXXXXXXXXX",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-name"
# }
```

### 環境変数の設定

```bash
# プロジェクトルートで実行
export AWS_REGION_PRIMARY=ap-northeast-1
export AWS_REGION_SECONDARY=ap-northeast-3
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export IMAGE_TAG=$(git rev-parse --short HEAD)
export PROJECT_NAME=template-cicd

# 確認
echo "Account ID: $AWS_ACCOUNT_ID"
echo "Image Tag: $IMAGE_TAG"
```

---

## Single Region テスト（EKS）

### 1. インフラのデプロイ

```bash
cd infra/terraform/eks

# 初期化
terraform init

# プラン確認（5-10分）
terraform plan

# デプロイ（15-20分）
terraform apply
# "yes" と入力して実行

# 出力の確認
terraform output
```

### 2. kubeconfig の設定

```bash
# EKSクラスタへの接続設定
aws eks update-kubeconfig \
  --region ap-northeast-1 \
  --name template-cicd-cluster

# 接続確認
kubectl cluster-info
kubectl get nodes

# 出力例:
# NAME                                           STATUS   ROLES    AGE   VERSION
# ip-10-0-1-234.ap-northeast-1.compute.internal  Ready    <none>   5m    v1.28.x
```

### 3. コンテナイメージのビルドとプッシュ

```bash
cd ../../../  # プロジェクトルートに戻る

# ECRログイン
make aws-login

# イメージビルド＆プッシュ（5-10分）
make aws-ecr-push IMAGE_TAG=test-v1

# ECR確認
aws ecr describe-images \
  --repository-name template-cicd/backend \
  --query 'imageDetails[0].[imageTags,imagePushedAt]' \
  --output table
```

### 4. アプリケーションのデプロイ

```bash
# Kubernetes manifestsをデプロイ
kubectl apply -f infra/kubernetes/namespace.yaml
kubectl apply -f infra/kubernetes/configmap.yaml
kubectl apply -f infra/kubernetes/secrets.yaml

# イメージタグを更新してデプロイ
# backend.yaml と frontend.yaml のイメージタグを修正
sed -i "s|backend:latest|$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION_PRIMARY.amazonaws.com/template-cicd/backend:test-v1|g" infra/kubernetes/backend.yaml
sed -i "s|frontend:latest|$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION_PRIMARY.amazonaws.com/template-cicd/frontend:test-v1|g" infra/kubernetes/frontend.yaml

kubectl apply -f infra/kubernetes/backend.yaml
kubectl apply -f infra/kubernetes/frontend.yaml
kubectl apply -f infra/kubernetes/keycloak.yaml

# デプロイ状態の確認
kubectl rollout status deployment/backend -n template-cicd --timeout=5m
kubectl rollout status deployment/frontend -n template-cicd --timeout=5m
```

### 5. 動作確認

```bash
# Pod状態の確認
kubectl get pods -n template-cicd

# 出力例（すべてRunningであることを確認）:
# NAME                        READY   STATUS    RESTARTS   AGE
# backend-xxxxxxxxx-xxxxx     1/1     Running   0          2m
# frontend-xxxxxxxxx-xxxxx    1/1     Running   0          2m
# keycloak-xxxxxxxxx-xxxxx    1/1     Running   0          2m

# ログ確認
kubectl logs -n template-cicd deployment/backend --tail=50
kubectl logs -n template-cicd deployment/frontend --tail=50

# サービス確認
kubectl get svc -n template-cicd

# ALBのDNS名を取得
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `template-cicd`)].DNSName' \
  --output text)

echo "ALB DNS: $ALB_DNS"
```

### 6. エンドポイントテスト

```bash
# ヘルスチェック
curl -I http://$ALB_DNS/health

# 期待される出力:
# HTTP/1.1 200 OK

# APIテスト
curl http://$ALB_DNS/api/users | jq .

# フロントエンドアクセス
curl -I http://$ALB_DNS/

# ブラウザでアクセス
echo "ブラウザで開く: http://$ALB_DNS"
```

### 7. データベース接続テスト

```bash
# Aurora接続情報を取得
DB_ENDPOINT=$(aws rds describe-db-clusters \
  --query 'DBClusters[?contains(DBClusterIdentifier, `template-cicd`)].Endpoint' \
  --output text)

echo "Aurora Endpoint: $DB_ENDPOINT"

# Secrets Managerから認証情報を取得
DB_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id template-cicd-aurora-credentials \
  --query SecretString \
  --output text)

echo $DB_SECRET | jq .

# Podからデータベース接続テスト
kubectl exec -it -n template-cicd deployment/backend -- \
  sh -c "echo 'SELECT version();' | psql \$DATABASE_URL"
```

---

## Single Region テスト（ECS）

### 1. インフラのデプロイ

```bash
cd infra/terraform/ecs

terraform init
terraform plan
terraform apply
```

### 2. タスク定義の確認

```bash
# タスク定義一覧
aws ecs list-task-definitions \
  --family-prefix template-cicd \
  --region ap-northeast-1

# 最新のタスク定義を確認
aws ecs describe-task-definition \
  --task-definition template-cicd-backend \
  --query 'taskDefinition.[family,revision,status]' \
  --output table
```

### 3. サービスのデプロイ

```bash
cd ../../..  # プロジェクトルートに戻る

# イメージのビルドとプッシュ
make aws-login
make aws-ecr-push IMAGE_TAG=test-v1

# サービス更新（新しいイメージを使用）
aws ecs update-service \
  --cluster template-cicd-cluster \
  --service template-cicd-backend \
  --force-new-deployment

aws ecs update-service \
  --cluster template-cicd-cluster \
  --service template-cicd-frontend \
  --force-new-deployment
```

### 4. 動作確認

```bash
# サービスステータス確認
aws ecs describe-services \
  --cluster template-cicd-cluster \
  --services template-cicd-backend template-cicd-frontend \
  --query 'services[].[serviceName,status,desiredCount,runningCount]' \
  --output table

# タスク一覧
aws ecs list-tasks \
  --cluster template-cicd-cluster \
  --service-name template-cicd-backend

# タスクログ確認
aws logs tail /ecs/template-cicd-backend --follow

# ALB確認
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `template-cicd`)].DNSName' \
  --output text)

curl http://$ALB_DNS/health
```

---

## Multi-Region テスト

### 1. マルチリージョンインフラのデプロイ

```bash
cd infra/terraform/multi-region

# 初期化
terraform init

# プラン確認（両リージョンの変更を表示）
terraform plan

# デプロイ（20-30分）
terraform apply
# "yes" と入力
```

### 2. 両リージョンの確認

```bash
# Primary Region（東京）の確認
echo "=== Primary Region: Tokyo ==="
aws eks describe-cluster \
  --region ap-northeast-1 \
  --name template-cicd-cluster-apne1 \
  --query 'cluster.[name,status]' \
  --output table

aws rds describe-db-clusters \
  --region ap-northeast-1 \
  --query 'DBClusters[?contains(DBClusterIdentifier, `primary`)].{ID:DBClusterIdentifier,Status:Status,Endpoint:Endpoint}' \
  --output table

# Secondary Region（大阪）の確認
echo "=== Secondary Region: Osaka ==="
aws eks describe-cluster \
  --region ap-northeast-3 \
  --name template-cicd-cluster-oska \
  --query 'cluster.[name,status]' \
  --output table

aws rds describe-db-clusters \
  --region ap-northeast-3 \
  --query 'DBClusters[?contains(DBClusterIdentifier, `secondary`)].{ID:DBClusterIdentifier,Status:Status,Endpoint:Endpoint}' \
  --output table
```

### 3. Aurora Global Database の確認

```bash
# Global Databaseステータス
aws rds describe-global-clusters \
  --global-cluster-identifier template-cicd-cluster-global \
  --query 'GlobalClusters[0].[GlobalClusterIdentifier,Status,GlobalClusterMembers]' \
  --output json | jq .

# レプリケーション遅延の確認
aws rds describe-db-clusters \
  --region ap-northeast-3 \
  --query 'DBClusters[?contains(DBClusterIdentifier, `secondary`)].ReplicationSourceIdentifier' \
  --output text
```

### 4. 両リージョンへのアプリケーションデプロイ

```bash
# または Makefileコマンドを使用
make multi-region-deploy-app

# 手動でデプロイする場合:

# Primary Region
aws eks update-kubeconfig \
  --region ap-northeast-1 \
  --name template-cicd-cluster-apne1

kubectl apply -f infra/kubernetes/namespace.yaml
kubectl apply -f infra/kubernetes/backend.yaml
kubectl apply -f infra/kubernetes/frontend.yaml

# Secondary Region
aws eks update-kubeconfig \
  --region ap-northeast-3 \
  --name template-cicd-cluster-oska

kubectl apply -f infra/kubernetes/namespace.yaml
kubectl apply -f infra/kubernetes/backend.yaml
kubectl apply -f infra/kubernetes/frontend.yaml
```

### 5. Route 53 ヘルスチェックの確認

```bash
# ヘルスチェック一覧
aws route53 list-health-checks \
  --query 'HealthChecks[?contains(to_string(Tags), `template-cicd`)].{ID:Id,Domain:HealthCheckConfig.FullyQualifiedDomainName,Type:HealthCheckConfig.Type}' \
  --output table

# ヘルスチェックステータス
PRIMARY_HC_ID=$(aws route53 list-health-checks \
  --query 'HealthChecks[?contains(to_string(Tags), `primary`)].Id' \
  --output text)

SECONDARY_HC_ID=$(aws route53 list-health-checks \
  --query 'HealthChecks[?contains(to_string(Tags), `secondary`)].Id' \
  --output text)

echo "Primary Health Check:"
aws route53 get-health-check-status --health-check-id $PRIMARY_HC_ID

echo "Secondary Health Check:"
aws route53 get-health-check-status --health-check-id $SECONDARY_HC_ID
```

### 6. 両リージョンのエンドポイントテスト

```bash
# Primary ALB
PRIMARY_ALB=$(aws elbv2 describe-load-balancers \
  --region ap-northeast-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `template-cicd`)].DNSName' \
  --output text)

echo "Primary ALB: $PRIMARY_ALB"
curl -I http://$PRIMARY_ALB/health

# Secondary ALB
SECONDARY_ALB=$(aws elbv2 describe-load-balancers \
  --region ap-northeast-3 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `template-cicd`)].DNSName' \
  --output text)

echo "Secondary ALB: $SECONDARY_ALB"
curl -I http://$SECONDARY_ALB/health
```

---

## 機能テスト

### 1. API 機能テスト

```bash
# バックエンドAPIのテスト
ALB_DNS="your-alb-dns-name.amazonaws.com"  # 実際のDNS名に置き換え

# ヘルスチェック
curl http://$ALB_DNS/health
# 期待: {"status":"ok"}

# ユーザー一覧取得（認証なし）
curl http://$ALB_DNS/api/users | jq .

# 認証付きAPIテスト（Keycloak使用時）
# 1. トークン取得
TOKEN=$(curl -X POST http://$ALB_DNS:8080/realms/myrealm/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=testuser" \
  -d "password=testpass123" \
  -d "grant_type=password" \
  -d "client_id=backend-client" \
  | jq -r .access_token)

echo "Token: $TOKEN"

# 2. 認証付きリクエスト
curl -H "Authorization: Bearer $TOKEN" \
  http://$ALB_DNS/api/protected | jq .
```

### 2. データベース読み書きテスト

```bash
# Podに接続してテスト
kubectl exec -it -n template-cicd deployment/backend -- sh

# Pod内で実行:
# データ挿入テスト
psql $DATABASE_URL -c "INSERT INTO users (name, email) VALUES ('Test User', 'test@example.com');"

# データ読み取りテスト
psql $DATABASE_URL -c "SELECT * FROM users LIMIT 5;"

# 接続プール確認
psql $DATABASE_URL -c "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database();"

exit
```

### 3. フロントエンド機能テスト

```bash
# フロントエンドの静的ファイル確認
curl http://$ALB_DNS/ | grep -i "template-cicd"

# JavaScriptバンドル確認
curl -I http://$ALB_DNS/assets/index.js

# 環境変数の確認（開発者ツールのコンソールで）
# ブラウザで開く
open http://$ALB_DNS
```

### 4. 認証フローテスト（Keycloak）

```bash
# Keycloak管理コンソールへのアクセス
KEYCLOAK_URL="http://$ALB_DNS:8080"
echo "Keycloak Admin: $KEYCLOAK_URL/admin"
echo "Username: admin"
echo "Password: (secrets.yamlで設定したパスワード)"

# レルム確認
curl $KEYCLOAK_URL/realms/myrealm | jq .realm

# クライアント確認
curl $KEYCLOAK_URL/realms/myrealm/.well-known/openid-configuration | jq .
```

---

## フェイルオーバーテスト

### 1. Primary Region 障害シミュレーション

```bash
# ⚠️ 注意: 本番環境では実施しないこと

# 方法1: ALBターゲットをすべて登録解除
PRIMARY_TG_ARN=$(aws elbv2 describe-target-groups \
  --region ap-northeast-1 \
  --query 'TargetGroups[?contains(TargetGroupName, `backend`)].TargetGroupArn' \
  --output text)

# ターゲット一覧取得
aws elbv2 describe-target-health \
  --region ap-northeast-1 \
  --target-group-arn $PRIMARY_TG_ARN

# 方法2: Podをすべて停止
kubectl scale deployment/backend -n template-cicd --replicas=0
kubectl scale deployment/frontend -n template-cicd --replicas=0
```

### 2. ヘルスチェックの監視

```bash
# Route 53ヘルスチェックが障害を検知するまで監視（約1-2分）
watch -n 10 "aws route53 get-health-check-status --health-check-id $PRIMARY_HC_ID | grep -i status"

# Secondary Regionが引き継ぐことを確認
echo "Secondary ALB: $SECONDARY_ALB"
curl http://$SECONDARY_ALB/health
```

### 3. DNS 解決の確認

```bash
# ※ Route 53のDNS設定が必要（main.tfのコメント解除）
# dig your-domain.com
# nslookup your-domain.com

# Secondaryへのトラフィック確認
curl -v http://your-domain.com/health
```

### 4. Aurora フェイルオーバーテスト

```bash
# ⚠️ 本番環境では計画的に実施

# Global Databaseのフェイルオーバー実行
aws rds failover-global-cluster \
  --global-cluster-identifier template-cicd-cluster-global \
  --target-db-cluster-identifier template-cicd-aurora-secondary \
  --region ap-northeast-3

# フェイルオーバー進行状況を監視（5-10分）
watch -n 30 "aws rds describe-global-clusters \
  --global-cluster-identifier template-cicd-cluster-global \
  --query 'GlobalClusters[0].[Status,GlobalClusterMembers]' \
  --output json | jq ."

# 完了後、セカンダリがプライマリに昇格したことを確認
aws rds describe-db-clusters \
  --region ap-northeast-3 \
  --query 'DBClusters[?contains(DBClusterIdentifier, `secondary`)].{ID:DBClusterIdentifier,Role:GlobalWriteForwardingStatus}' \
  --output table
```

### 5. リカバリ（フェイルバック）

```bash
# Primary Regionの復旧
kubectl scale deployment/backend -n template-cicd --replicas=2
kubectl scale deployment/frontend -n template-cicd --replicas=2

# ヘルスチェックの回復を待つ（約2-3分）
watch -n 10 "aws route53 get-health-check-status --health-check-id $PRIMARY_HC_ID"

# Aurora Global Databaseを元に戻す（オプション）
aws rds failover-global-cluster \
  --global-cluster-identifier template-cicd-cluster-global \
  --target-db-cluster-identifier template-cicd-aurora-primary \
  --region ap-northeast-1
```

---

## パフォーマンステスト

### 1. 負荷テスト準備

```bash
# Apache Benchのインストール
# macOS
brew install ab

# Linux
sudo apt-get install apache2-utils

# または hey (より高機能)
go install github.com/rakyll/hey@latest
```

### 2. 基本的な負荷テスト

```bash
# 100リクエスト、10並行
ab -n 100 -c 10 http://$ALB_DNS/health

# より詳細なテスト
hey -n 1000 -c 50 -q 10 http://$ALB_DNS/api/users

# 結果の見方:
# - Requests/sec: スループット
# - Latency distribution: レスポンスタイム分布
# - Status code distribution: HTTPステータスコード
```

### 3. データベース負荷テスト

```bash
# pgbenchを使用（Pod内で実行）
kubectl exec -it -n template-cicd deployment/backend -- sh

# Pod内で:
pgbench -i $DATABASE_URL  # 初期化
pgbench -c 10 -j 2 -t 1000 $DATABASE_URL  # 負荷テスト

exit
```

### 4. オートスケーリングテスト

```bash
# HPA（Horizontal Pod Autoscaler）の設定
kubectl autoscale deployment backend \
  -n template-cicd \
  --cpu-percent=50 \
  --min=2 \
  --max=10

# 負荷をかけてスケーリングを確認
hey -n 10000 -c 100 http://$ALB_DNS/api/users &

# スケーリングの監視
watch -n 5 "kubectl get hpa -n template-cicd && kubectl get pods -n template-cicd"
```

### 5. リージョン間レイテンシ測定

```bash
# Primary -> Secondary間の遅延
time curl -I http://$PRIMARY_ALB/health
time curl -I http://$SECONDARY_ALB/health

# 複数回実行して平均を取る
for i in {1..10}; do
  curl -o /dev/null -s -w "Primary: %{time_total}s\n" http://$PRIMARY_ALB/health
  curl -o /dev/null -s -w "Secondary: %{time_total}s\n" http://$SECONDARY_ALB/health
done
```

---

## クリーンアップ

### テスト環境のクリーンアップ

```bash
# ⚠️ 注意: すべてのリソースが削除されます

# Single Region（EKS）
cd infra/terraform/eks
terraform destroy
# "yes" と入力

# Single Region（ECS）
cd ../ecs
terraform destroy

# Multi-Region
cd ../multi-region
terraform destroy
# または
make multi-region-destroy

# ECRイメージの削除（オプション）
aws ecr batch-delete-image \
  --repository-name template-cicd/backend \
  --image-ids imageTag=test-v1

aws ecr batch-delete-image \
  --repository-name template-cicd/frontend \
  --image-ids imageTag=test-v1
```

### Kubernetes リソースのみ削除

```bash
# Namespaceごと削除
kubectl delete namespace template-cicd

# または個別に削除
kubectl delete -f infra/kubernetes/
```

### 削除確認

```bash
# EKSクラスタの削除確認
aws eks list-clusters --region ap-northeast-1
aws eks list-clusters --region ap-northeast-3

# Aurora削除確認
aws rds describe-db-clusters \
  --query 'DBClusters[?contains(DBClusterIdentifier, `template-cicd`)].DBClusterIdentifier'

# ロードバランサー削除確認
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `template-cicd`)].LoadBalancerName'

# 課金が発生しないことを確認
aws ce get-cost-and-usage \
  --time-period Start=2026-01-01,End=2026-01-05 \
  --granularity DAILY \
  --metrics BlendedCost \
  --query 'ResultsByTime[*].[TimePeriod.Start,Total.BlendedCost.Amount]' \
  --output table
```

---

## トラブルシューティング

### Pod が起動しない

```bash
# イベント確認
kubectl describe pod <pod-name> -n template-cicd

# よくあるエラー:
# - ImagePullBackOff: ECRイメージが見つからない
# - CrashLoopBackOff: アプリケーションエラー
# - Pending: リソース不足

# ログ確認
kubectl logs <pod-name> -n template-cicd --previous
```

### データベース接続エラー

```bash
# Secrets確認
kubectl get secret -n template-cicd
kubectl describe secret aurora-credentials -n template-cicd

# Security Group確認
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*aurora*" \
  --query 'SecurityGroups[*].[GroupId,GroupName,IpPermissions]' \
  --output json | jq .
```

### ALB がトラフィックを転送しない

```bash
# ターゲットヘルス確認
aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN

# ターゲットグループ設定確認
aws elbv2 describe-target-groups \
  --target-group-arns $TARGET_GROUP_ARN \
  --query 'TargetGroups[*].HealthCheckPath'
```

### Terraform エラー

```bash
# ステート確認
terraform show

# ステートのリフレッシュ
terraform refresh

# 特定のリソースを再作成
terraform taint aws_eks_cluster.main
terraform apply

# ロック解除（慎重に）
terraform force-unlock <lock-id>
```

---

## テストチェックリスト

### デプロイ前

- [ ] AWS 認証情報が設定されている
- [ ] 必要なツールがインストールされている
- [ ] 環境変数が設定されている
- [ ] ECR リポジトリが作成されている

### デプロイ後

- [ ] EKS/ECS クラスタが正常に起動している
- [ ] Pod が全て Running 状態である
- [ ] Aurora クラスタが利用可能である
- [ ] ALB がヘルスチェックに合格している
- [ ] Route 53 ヘルスチェックが成功している

### 機能テスト

- [ ] ヘルスエンドポイントが 200 を返す
- [ ] API エンドポイントが正常にレスポンスを返す
- [ ] データベース読み書きができる
- [ ] 認証フローが正常に動作する
- [ ] フロントエンドが正しく表示される

### Multi-Region

- [ ] 両リージョンのクラスタが起動している
- [ ] Aurora Global Database のレプリケーションが動作している
- [ ] 両リージョンのヘルスチェックが成功している
- [ ] フェイルオーバーが正常に動作する

### クリーンアップ

- [ ] 全てのリソースが削除されている
- [ ] 予期しない課金が発生していない

---

## 参考資料

- [AWS EKS ベストプラクティス](https://aws.github.io/aws-eks-best-practices/)
- [Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html)
- [Route 53 ヘルスチェック](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks-creating.html)
- [Kubernetes 公式ドキュメント](https://kubernetes.io/docs/home/)

---

## サポート

問題が発生した場合:

1. ログを確認: `kubectl logs`, CloudWatch Logs
2. AWS Health Dashboard: サービスの障害情報
3. プロジェクトの Issue を作成

**テストの成功を祈ります！** 🚀
