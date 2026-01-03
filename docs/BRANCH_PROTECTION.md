# ブランチ保護ルールの設定

このドキュメントでは、GitHub で main ブランチにブランチ保護ルールを設定し、CI チェックが失敗した場合に push をリジェクトする方法を説明します。

## 概要

ブランチ保護ルールを設定することで：

- main ブランチへの直接 push を禁止
- プルリクエストを必須化
- CI チェック（GitHub Actions）の成功を必須化
- コードレビューの必須化（オプション）

## 方法 1: GitHub Web UI で設定

### 手順

1. **リポジトリの設定ページに移動**

   - GitHub のリポジトリページを開く
   - `Settings` タブをクリック

2. **ブランチ保護ルールのページに移動**

   - 左サイドバーの `Branches` をクリック
   - `Add branch protection rule` ボタンをクリック

3. **ブランチ名パターンを指定**

   - `Branch name pattern` に `main` と入力

4. **保護ルールを設定**
   以下の項目にチェックを入れます：

   #### 必須設定

   - ✅ **Require a pull request before merging**
     - main ブランチへの直接 push を禁止
     - プルリクエスト経由のみマージ可能に
   - ✅ **Require status checks to pass before merging**
     - CI チェックの成功を必須化
     - ✅ **Require branches to be up to date before merging**
       - マージ前に最新の main ブランチの変更を取り込むことを必須化
     - 以下のステータスチェックを選択：
       - `Backend Tests`
       - `Frontend Tests`

   #### 推奨設定

   - ✅ **Require approvals** (オプション)
     - コードレビューの承認を必須化
     - 必要な承認数を設定（推奨: 1）
   - ✅ **Dismiss stale pull request approvals when new commits are pushed**
     - 新しいコミットが push された際に古い承認を無効化
   - ⬜ **Do not allow bypassing the above settings**
     - 管理者も保護ルールを回避できないようにする
     - ⚠️ 当面は管理者が main ブランチに直接 push できるよう、この項目はチェックを外しておきます
   - ✅ **Require linear history**
     - マージコミットを禁止し、リベースまたはスカッシュマージを強制（オプション）

5. **保存**
   - `Create` ボタンをクリックして保護ルールを作成

## 方法 2: GitHub CLI で自動設定

GitHub CLI (gh) を使用して、コマンドラインから設定を行うことができます。

### 前提条件

```bash
# GitHub CLIのインストール確認
gh --version

# 認証（未認証の場合）
gh auth login
```

### 設定スクリプトの実行

プロジェクトルートに用意されている設定スクリプトを実行します：

```bash
./scripts/setup-branch-protection.sh
```

または手動で以下のコマンドを実行：

```bash
# リポジトリの所有者名とリポジトリ名を設定
REPO_OWNER="your-github-username"
REPO_NAME="template-cicd"

# ブランチ保護ルールを設定
# 注意: enforce_admins=false により、管理者は保護ルールを回避できます
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/$REPO_OWNER/$REPO_NAME/branches/main/protection" \
  -f required_status_checks='{"strict":true,"contexts":["Backend Tests","Frontend Tests"]}' \
  -f enforce_admins=false \
  -f required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true}' \
  -f restrictions=null \
  -F allow_force_pushes=false \
  -F allow_deletions=false
```

## 動作確認

設定が正しく適用されているか確認します：

1. **main ブランチへの直接 push をテスト**

   ```bash
   git checkout main
   echo "test" >> README.md
   git add README.md
   git commit -m "test commit"
   git push origin main
   ```

   エラーメッセージが表示されれば成功：

   ```
   remote: error: GH006: Protected branch update failed for refs/heads/main.
   ```

2. **プルリクエストでの動作確認**
   - 新しいブランチを作成してプルリクエストを開く
   - CI チェックが完了するまで "Merge" ボタンが無効化されることを確認
   - CI が失敗した場合はマージできないことを確認

## トラブルシューティング

### CI チェックの名前が見つからない

- GitHub Actions のワークフローで Job の名前が正しく設定されているか確認
- ワークフローが少なくとも 1 回実行されている必要があります
- [ci.yml](.github/workflows/ci.yml) の `jobs.*.name` の値を確認

### 管理者による直接 push

現在の設定では、管理者はブランチ保護ルールを回避して main ブランチに直接 push することができます。

**注意事項：**

- 管理者であっても、可能な限りプルリクエストを使用することを推奨します
- CI チェックを回避して push する場合は、事前にローカルで `./scripts/ci-check.sh` を実行してください
- 緊急時の修正やホットフィックスにのみ直接 push を使用してください

**より厳格な保護を有効にする場合：**

管理者にも保護ルールを適用したい場合は：

1. GitHub Settings > Branches > Branch protection rules
2. main ブランチのルールを編集
3. `Do not allow bypassing the above settings` にチェックを入れる

または、スクリプトの `enforce_admins` を `true` に変更して再実行してください。

### プルリクエストなしで push したい場合

緊急時の対応：

1. Settings > Branches でブランチ保護ルールを一時的に削除
2. 作業を完了
3. 保護ルールを再設定

## CI/CD ワークフロー

このプロジェクトの CI ワークフローは以下のチェックを実行します：

### Backend Tests

- Rust のテスト実行
- Clippy による lint

### Frontend Tests

- TypeScript の lint
- Vitest によるテスト実行
- ビルドの成功確認

詳細は [.github/workflows/ci.yml](../.github/workflows/ci.yml) を参照してください。

## ローカルでの CI 確認

プルリクエストを作成する前に、ローカルで CI チェックと同じテストを実行できます：

```bash
./scripts/ci-check.sh
```

これにより、GitHub Actions で実行されるのと同じチェックをローカルで実行できます。

## 参考リンク

- [GitHub Documentation: About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [GitHub Documentation: Managing a branch protection rule](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/managing-a-branch-protection-rule)
- [GitHub REST API: Branch protection](https://docs.github.com/en/rest/branches/branch-protection)
