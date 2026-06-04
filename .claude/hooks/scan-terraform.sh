#!/usr/bin/env bash
# Hook: scan-terraform.sh (PostToolUse on Write|Edit)
# Purpose: After editing a Terraform file, actually RUN the static scans on the
#          changed module — terraform fmt check + Checkov — and surface results.
# Why: Replaces the in-loop scanning the (yanked) awslabs.terraform-mcp-server used
#      to provide. Catches misformatting and security misconfig while editing,
#      before commit/plan. Non-blocking: exit 0 always so it never halts work.
# How: Resolves the module directory from the edited file, runs fmt -check and
#      `checkov -d <dir>` scoped to that dir only (fast). Skips gracefully if a
#      tool is missing. Hard-capped with `timeout` so a slow scan can't stall.

set -uo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only act on Terraform files.
[ -z "$FILE_PATH" ] && exit 0
echo "$FILE_PATH" | grep -qE '\.tf$' || exit 0

TF_DIR=$(dirname "$FILE_PATH")
[ -d "$TF_DIR" ] || exit 0

echo "── scan-terraform: ${TF_DIR}/ ──"

# 1) Formatting (instant, no init required).
if command -v terraform >/dev/null 2>&1; then
  if ! terraform fmt -check -diff "$TF_DIR" >/tmp/tf-fmt.$$ 2>&1; then
    echo "✗ fmt: needs formatting — run 'terraform fmt ${TF_DIR}/'"
    cat /tmp/tf-fmt.$$
  else
    echo "✓ fmt: clean"
  fi
  rm -f /tmp/tf-fmt.$$
fi

# 2) Checkov security scan, scoped to the edited module (skip if not installed).
if command -v checkov >/dev/null 2>&1; then
  if timeout 90 checkov -d "$TF_DIR" --compact --quiet --soft-fail >/tmp/ckv.$$ 2>&1; then
    # --soft-fail makes checkov exit 0 even on findings; grep the summary instead.
    if grep -qE 'Failed checks: [1-9]' /tmp/ckv.$$; then
      echo "⚠ checkov: findings below (review before commit)"
      grep -E 'Check:|FAILED|Failed checks:|File:' /tmp/ckv.$$ | head -40
    else
      echo "✓ checkov: no failed checks"
    fi
  else
    echo "⚠ checkov: scan timed out or errored (run manually: checkov -d ${TF_DIR})"
  fi
  rm -f /tmp/ckv.$$
else
  echo "ℹ checkov not installed — run 'uv tool install checkov' to enable in-loop scanning"
fi

# Always informational — never block.
exit 0
