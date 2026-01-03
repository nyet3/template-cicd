# Keycloak Configuration

## テスト環境セットアップ

1. Keycloakコンテナ起動:
```bash
docker-compose -f docker-compose.test.yml up keycloak -d
```

2. Admin Console にアクセス:
- URL: http://localhost:8180
- Username: admin
- Password: admin

3. Realmインポート:
- 左上のドロップダウンから "Create Realm" を選択
- `realm-export.json` をインポート

## テストユーザー

- Username: testuser
- Password: testpass123
- Email: test@example.com

## クライアント

### backend-client
- Type: Confidential
- Service Account: Enabled

### frontend-client
- Type: Public
- Standard Flow: Enabled
- Valid Redirect URIs: 設定済み

## 本番環境

本番環境では、以下を設定してください:

1. SSL/TLS 有効化
2. 強固なパスワードポリシー
3. 適切なRedirect URI制限
4. セキュアなクライアントシークレット管理
5. 定期的なトークン更新設定
