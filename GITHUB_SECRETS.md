# GitHub Secrets 設定ガイド

GitHub Actions CI/CD を使用するために、以下のシークレットを設定してください。

## 必須シークレット

### コンテナレジストリ

1. `REGISTRY_URL`
   - コンテナレジストリのURL
   - 例: `ghcr.io/your-org` または `your-account.dkr.ecr.us-east-1.amazonaws.com`

2. `REGISTRY_USERNAME`
   - レジストリへの認証ユーザー名
   - GitHub Container Registry の場合: GitHubユーザー名
   - AWS ECR の場合: AWS Access Key ID

3. `REGISTRY_PASSWORD`
   - レジストリへの認証パスワード/トークン
   - GitHub Container Registry の場合: Personal Access Token (packages:write権限)
   - AWS ECR の場合: AWS Secret Access Key

### Kubernetes 設定

4. `KUBECONFIG_STAGING`
   - ステージング環境の kubeconfig ファイル内容
   - Base64エンコードせず、そのまま設定

5. `KUBECONFIG_PRODUCTION`
   - 本番環境の kubeconfig ファイル内容
   - Base64エンコードせず、そのまま設定

## シークレットの設定方法

### GitHub UI から設定

1. リポジトリページへ移動
2. Settings → Secrets and variables → Actions
3. "New repository secret" をクリック
4. Name と Secret を入力
5. "Add secret" をクリック

### 環境別シークレット（オプション）

より細かい制御が必要な場合、環境別にシークレットを設定できます:

1. Settings → Environments
2. "New environment" で `staging` と `production` を作成
3. 各環境にシークレットを設定

## kubeconfig の取得方法

### 一般的な Kubernetes クラスター

```bash
# 既存の kubeconfig をコピー
cat ~/.kube/config
```

### Amazon EKS

```bash
aws eks update-kubeconfig --name your-cluster-name --region us-east-1
cat ~/.kube/config
```

### Google GKE

```bash
gcloud container clusters get-credentials your-cluster-name --zone us-central1-a
cat ~/.kube/config
```

### Azure AKS

```bash
az aks get-credentials --resource-group your-rg --name your-cluster-name
cat ~/.kube/config
```

## セキュリティのベストプラクティス

1. **最小権限の原則**: CI/CD 用のサービスアカウントは必要最小限の権限のみ付与
2. **定期的なローテーション**: 認証情報を定期的に更新
3. **監査ログ**: デプロイメントアクティビティを監視
4. **環境分離**: ステージングと本番の認証情報を完全に分離

## AWS RDS 接続情報

本番環境で AWS RDS を使用する場合、Kubernetes Secrets に以下を設定:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: backend-secrets
  namespace: template-cicd
type: Opaque
stringData:
  DATABASE_URL: "postgresql://username:password@your-rds-endpoint.rds.amazonaws.com:5432/dbname"
```

## トラブルシューティング

### デプロイが失敗する

1. シークレットが正しく設定されているか確認
2. kubeconfig の認証情報が有効か確認
3. レジストリへのプッシュ権限があるか確認

### イメージのプル失敗

1. Kubernetes クラスターからレジストリへの認証設定
2. ImagePullSecrets の設定

```bash
kubectl create secret docker-registry regcred \
  --docker-server=$REGISTRY_URL \
  --docker-username=$REGISTRY_USERNAME \
  --docker-password=$REGISTRY_PASSWORD \
  --namespace=template-cicd
```
