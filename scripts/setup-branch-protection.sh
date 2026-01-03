#!/bin/bash
set -e

# Branch Protection Setup Script
# This script configures branch protection rules for the main branch using GitHub CLI

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    print_error "GitHub CLI (gh) is not installed."
    echo "Please install it from: https://cli.github.com/"
    echo ""
    echo "Installation commands:"
    echo "  macOS:   brew install gh"
    echo "  Linux:   See https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
    echo "  Windows: See https://github.com/cli/cli#windows"
    exit 1
fi

print_section "🔒 GitHub Branch Protection Setup"

# Check if authenticated
print_info "Checking GitHub authentication..."
if ! gh auth status &> /dev/null; then
    print_error "Not authenticated with GitHub CLI"
    echo "Please run: gh auth login"
    exit 1
fi
print_success "Authenticated with GitHub CLI"

# Get repository information
print_info "Getting repository information..."
REPO_INFO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
if [ -z "$REPO_INFO" ]; then
    print_error "Could not determine repository information"
    echo "Please ensure you are in a git repository with a GitHub remote"
    exit 1
fi
print_success "Repository: $REPO_INFO"

# Confirm action
echo ""
print_warning "This will configure branch protection for the 'main' branch"
echo "The following rules will be applied:"
echo "  • Require pull request before merging"
echo "  • Require status checks to pass (Backend Tests, Frontend Tests)"
echo "  • Require branches to be up to date before merging"
echo "  • Require at least 1 approving review"
echo "  • Dismiss stale pull request approvals when new commits are pushed"
echo "  • Allow administrators to bypass these rules"
echo "  • Prevent force pushes"
echo "  • Prevent branch deletion"
echo ""
read -p "Do you want to continue? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Operation cancelled"
    exit 0
fi

# Apply branch protection
print_info "Applying branch protection rules..."

# Note: GitHub API requires all protection rules to be set at once
# We build the JSON payload and send it via the API
cat > /tmp/branch-protection.json <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Backend Tests", "Frontend Tests"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": false,
  "lock_branch": false,
  "allow_fork_syncing": false
}
EOF

if gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "/repos/$REPO_INFO/branches/main/protection" \
    --input /tmp/branch-protection.json > /dev/null 2>&1; then
    print_success "Branch protection rules applied successfully!"
else
    print_error "Failed to apply branch protection rules"
    echo ""
    echo "This could be due to:"
    echo "  • Insufficient permissions (requires admin access to the repository)"
    echo "  • The status check names don't match the workflow job names"
    echo "  • The workflows haven't run yet (status checks need to exist first)"
    echo ""
    print_info "You can also configure this manually:"
    echo "  1. Go to GitHub repository Settings > Branches"
    echo "  2. Add a branch protection rule for 'main'"
    echo "  3. Configure the settings as described above"
    echo ""
    print_info "For more details, see: docs/BRANCH_PROTECTION.md"
    rm -f /tmp/branch-protection.json
    exit 1
fi

# Clean up
rm -f /tmp/branch-protection.json

print_section "✨ Setup Complete"
echo ""
print_info "Next steps:"
echo "  1. Try to push directly to main - it should be rejected"
echo "  2. Create a pull request to test the workflow"
echo "  3. Verify that CI checks are required before merging"
echo ""
print_info "To verify the settings:"
echo "  gh api /repos/$REPO_INFO/branches/main/protection | jq"
echo ""
print_info "For more information, see:"
echo "  docs/BRANCH_PROTECTION.md"
