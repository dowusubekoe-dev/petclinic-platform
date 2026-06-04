#!/usr/bin/env bash
set -euo pipefail

#
# bootstrap-state.sh — One-time setup of the Terraform remote state backend.
#
# Provisions the resources Terraform needs BEFORE `terraform init`:
#   - S3 bucket   petclinic-terraform-state-<account-id>
#       * versioning enabled
#       * server-side encryption (AES256 / SSE-S3)
#       * all four public-access-block settings on
#   - DynamoDB table  petclinic-terraform-locks  (LockID partition key, String)
#
# The script is IDEMPOTENT — safe to run repeatedly. Existing resources are
# detected and their settings re-applied rather than recreated.
#
# Usage:
#   ./scripts/bootstrap-state.sh                 # region us-east-1 (default)
#   ./scripts/bootstrap-state.sh --region us-east-1
#
# Requires: AWS CLI v2 configured with credentials that can create S3/DynamoDB.
#

REGION="us-east-1"
TABLE_NAME="petclinic-terraform-locks"

usage() {
  echo "Usage: $0 [--region <aws-region>]"
  echo "  --region   AWS region for the state bucket and lock table (default: us-east-1)"
  exit 1
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      [[ $# -ge 2 ]] || { echo "Error: --region requires a value"; usage; }
      REGION="$2"
      shift 2
      ;;
    --region=*)
      REGION="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: unknown argument '$1'"
      usage
      ;;
  esac
done

# --- Resolve account ID and bucket name ---
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET_NAME="petclinic-terraform-state-${ACCOUNT_ID}"

echo "============================================"
echo "  Terraform state backend bootstrap"
echo "  Account: ${ACCOUNT_ID}"
echo "  Region:  ${REGION}"
echo "  Bucket:  ${BUCKET_NAME}"
echo "  Table:   ${TABLE_NAME}"
echo "============================================"
echo ""

# --- Step 1: S3 bucket ---
echo "[1/5] Creating S3 state bucket: ${BUCKET_NAME}"
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "  -> Bucket already exists. Skipping creation."
else
  if [[ "${REGION}" == "us-east-1" ]]; then
    # us-east-1 must NOT pass a LocationConstraint.
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}" >/dev/null
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${REGION}" \
      --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
  fi
  echo "  -> Bucket created."
fi

# --- Step 2: Versioning (idempotent put) ---
echo "[2/5] Enabling bucket versioning"
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled
echo "  -> Versioning enabled."

# --- Step 3: Server-side encryption (idempotent put) ---
echo "[3/5] Enabling server-side encryption (AES256)"
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
echo "  -> Encryption enabled."

# --- Step 4: Block all public access (idempotent put) ---
echo "[4/5] Blocking all public access"
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
aws s3api put-bucket-tagging \
  --bucket "${BUCKET_NAME}" \
  --tagging 'TagSet=[{Key=Project,Value=petclinic},{Key=ManagedBy,Value=bootstrap-script},{Key=Purpose,Value=terraform-state}]'
echo "  -> Public access blocked (all 4 settings)."

# --- Step 5: DynamoDB lock table ---
echo "[5/5] Creating DynamoDB lock table: ${TABLE_NAME}"
if aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${REGION}" >/dev/null 2>&1; then
  echo "  -> Table already exists. Skipping creation."
else
  aws dynamodb create-table \
    --table-name "${TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}" \
    --tags Key=Project,Value=petclinic Key=ManagedBy,Value=bootstrap-script Key=Purpose,Value=terraform-state-lock \
    >/dev/null
  echo "  -> Table created. Waiting for it to become active..."
  aws dynamodb wait table-exists --table-name "${TABLE_NAME}" --region "${REGION}"
  echo "  -> Table is active."
fi

echo ""
echo "============================================"
echo "  Bootstrap complete."
echo ""
echo "  Initialize an environment with:"
echo ""
echo "    cd terraform/environments/dev"
echo "    terraform init -backend-config=\"bucket=${BUCKET_NAME}\""
echo ""
echo "  (replace 'dev' with 'prod' for the prod environment)"
echo "============================================"
