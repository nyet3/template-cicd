# GitHub Secrets 設定ガイド

GitHub Actions CI/CD を使用するために、以下のシークレットを設定してください。

> **注意**: これらのシークレットが設定されていない場合、デプロイ関連のジョブは自動的にスキップされます。CI（テスト、ビルド、Lint）のみが実行されます。

## 必須シークレット (Multi-Region Production)

### AWS 認証情報

1. `AWS_ACCESS_KEY_ID`

   - AWS アクセスキー ID
   - IAM ユーザーまたはロールのアクセスキー
   - 必要な権限: ECR, EKS, RDS, Route53, Secrets Manager

2. `AWS_SECRET_ACCESS_KEY`
   - AWS シークレットアクセスキー
   - 上記アクセスキー ID に対応するシークレットキー

### 必要な IAM ポリシー

CI/CD ユーザーには以下の権限が必要です：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters",
        "eks:UpdateClusterConfig"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["sts:GetCallerIdentity"],
      "Resource": "*"
    }
  ]
}
```

## シークレットの設定方法

### シークレット未設定時の動作

GitHub Secrets が設定されていない場合：

- **CI ワークフロー** (`ci.yml`): 正常に実行されます（テスト、Lint、ビルド）
- **CD ワークフロー** (`cd-staging.yml`, `cd-production.yml`): ビルド・デプロイジョブがスキップされます
- **Multi-Region Deployment** (`deploy-multi-region.yml`): AWS 関連ジョブがスキップされます

これにより、Secrets が未設定でも CI/CD パイプラインがエラーにならず、開発を継続できます。

### GitHub UI から設定

1. リポジトリページへ移動
2. Settings → Secrets and variables → Actions
3. "New repository secret" をクリック
4. Name と Secret を入力
5. "Add secret" をクリック

### 設定例

```bash
# AWS認証情報を確認
aws sts get-caller-identity

# GitHub CLIで設定 (オプション)
gh secret set AWS_ACCESS_KEY_ID -b "YOUR_ACCESS_KEY_ID"
gh secret set AWS_SECRET_ACCESS_KEY -b "YOUR_SECRET_ACCESS_KEY"
```

## 環境別シークレット（Production Environment）

本番環境への自動デプロイには承認フローを追加できます:

1. Settings → Environments
2. "New environment" で `production` を作成
3. "Required reviewers" を設定（承認者を指定）
4. "Deployment branches" でブランチを制限（例: main のみ）

## ローカル開発用のシークレット (オプション)

### コンテナレジストリ (Staging)

以下はステージング環境用のオプション設定です：

1. `REGISTRY_URL`

   - コンテナレジストリの URL
   - 例: `ghcr.io/your-org`

2. `REGISTRY_USERNAME`

   - レジストリへの認証ユーザー名
   - GitHub Container Registry の場合: GitHub ユーザー名

3. `REGISTRY_PASSWORD`
   - レジストリへの認証パスワード/トークン
   - GitHub Container Registry の場合: Personal Access Token (packages:write 権限)

### Kubernetes 設定 (Staging)

4. `KUBECONFIG_STAGING`
   - ステージング環境の kubeconfig ファイル内容
   - Base64 エンコードせず、そのまま設定

## Multi-Region Deployment

### リージョン設定

デフォルトのリージョン設定：

- **Primary**: `ap-northeast-1` (東京)
- **Secondary**: `ap-northeast-3` (大阪)

リージョンを変更する場合は、以下のファイルを編集：

- `.github/workflows/deploy-multi-region.yml`
- `Makefile`
- `infra/terraform/multi-region/variables.tf`

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
