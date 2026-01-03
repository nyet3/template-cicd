#!/bin/bash
set -e

# CI/CD Check Script
# This script runs all the same checks that CI/CD runs
# Use this to verify your changes before pushing to ensure CI/CD passes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Track failures
FAILED=0

# Backend Tests
print_section "🦀 Backend CI Checks"

print_info "Running cargo test..."
if cd "$PROJECT_ROOT/backend" && cargo test --verbose; then
    print_success "Backend tests passed"
else
    print_error "Backend tests failed"
    FAILED=1
fi

print_info "Running cargo clippy..."
if cd "$PROJECT_ROOT/backend" && cargo clippy -- -D warnings; then
    print_success "Backend clippy checks passed"
else
    print_error "Backend clippy checks failed"
    FAILED=1
fi

# Frontend Tests
print_section "⚛️  Frontend CI Checks"

print_info "Installing dependencies..."
if cd "$PROJECT_ROOT/frontend" && npm ci; then
    print_success "Dependencies installed"
else
    print_error "Failed to install dependencies"
    FAILED=1
fi

print_info "Running linter..."
if cd "$PROJECT_ROOT/frontend" && npm run lint; then
    print_success "Frontend linting passed"
else
    print_error "Frontend linting failed"
    FAILED=1
fi

print_info "Running tests..."
if cd "$PROJECT_ROOT/frontend" && npm test -- --run; then
    print_success "Frontend tests passed"
else
    print_error "Frontend tests failed"
    FAILED=1
fi

print_info "Building frontend..."
if cd "$PROJECT_ROOT/frontend" && npm run build; then
    print_success "Frontend build successful"
else
    print_error "Frontend build failed"
    FAILED=1
fi

# Summary
print_section "📊 Summary"

if [ $FAILED -eq 0 ]; then
    print_success "All CI checks passed! ✨"
    print_info "Your code is ready to push. CI/CD should pass successfully."
    exit 0
else
    print_error "Some CI checks failed! ❌"
    print_warning "Please fix the errors above before pushing."
    exit 1
fi
