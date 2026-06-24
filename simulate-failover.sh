#!/bin/bash
# simulate-failover.sh - DR failover simulation for multicloud CDN
# Tests that CloudFront fails over from S3 to Azure Blob Storage

set -e

BUCKET=$(terraform -chdir=terraform/aws output -raw s3_bucket_name)
CDN_URL=$(terraform -chdir=terraform/aws output -raw cdn_url)
DISTRIBUTION_ID=$(terraform -chdir=terraform/aws output -raw cloudfront_distribution_id)

echo "============================================"
echo "  Multicloud CDN - DR Failover Simulation"
echo "============================================"
echo ""
echo "S3 Bucket:       $BUCKET"
echo "CDN URL:         $CDN_URL"
echo "Distribution ID: $DISTRIBUTION_ID"
echo ""

# --- PRE-FAILOVER: Verify primary origin is serving ---
verify_origin() {
  echo "[TEST] Requesting $CDN_URL ..."
  RESPONSE=$(curl -s "$CDN_URL")
  echo "       Response: $RESPONSE"
  echo ""
  if echo "$RESPONSE" | grep -q "AWS S3"; then
    echo "✅ Traffic served from PRIMARY (AWS S3)"
  elif echo "$RESPONSE" | grep -q "Azure Blob"; then
    echo "✅ Traffic served from FAILOVER (Azure Blob Storage)"
  else
    echo "❌ Unexpected response"
  fi
  echo ""
}

# --- SIMULATE S3 FAILURE: Deny CloudFront access ---
break_primary() {
  echo "[CHAOS] Denying CloudFront access to S3 bucket..."
  aws s3api put-bucket-policy --bucket "$BUCKET" --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"DenyAll\",
      \"Effect\": \"Deny\",
      \"Principal\": \"*\",
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::${BUCKET}/*\"
    }]
  }"
  echo "       S3 bucket policy set to DENY ALL"
  echo ""
  echo "[WAIT] Invalidating CloudFront cache to force origin fetch..."
  aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths "/*" > /dev/null
  echo "       Waiting 30s for invalidation to propagate..."
  sleep 30
}

# --- RESTORE: Re-allow CloudFront access ---
restore_primary() {
  echo "[RESTORE] Restoring S3 bucket policy for CloudFront OAC..."
  DIST_ARN="arn:aws:cloudfront::$(aws sts get-caller-identity --query Account --output text):distribution/${DISTRIBUTION_ID}"
  aws s3api put-bucket-policy --bucket "$BUCKET" --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"AllowCloudFrontOAC\",
      \"Effect\": \"Allow\",
      \"Principal\": {\"Service\": \"cloudfront.amazonaws.com\"},
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::${BUCKET}/*\",
      \"Condition\": {
        \"StringEquals\": {
          \"AWS:SourceArn\": \"${DIST_ARN}\"
        }
      }
    }]
  }"
  echo "       S3 bucket policy restored"
  echo ""
}

# --- MAIN ---
case "${1:-}" in
  test)
    echo "--- Step 1: Verify primary origin ---"
    verify_origin
    ;;
  break)
    echo "--- Simulating S3 failure (DR event) ---"
    break_primary
    echo "--- Verifying failover to Azure ---"
    verify_origin
    ;;
  restore)
    echo "--- Restoring primary origin ---"
    restore_primary
    echo "--- Verifying primary restored ---"
    sleep 10
    verify_origin
    ;;
  full)
    echo "--- Step 1: Verify primary origin ---"
    verify_origin
    echo "--- Step 2: Simulating S3 failure (DR event) ---"
    break_primary
    echo "--- Step 3: Verifying failover to Azure ---"
    verify_origin
    echo "--- Step 4: Restoring primary origin ---"
    restore_primary
    echo "--- Step 5: Verifying primary restored ---"
    sleep 10
    verify_origin
    echo ""
    echo "============================================"
    echo "  DR Failover Simulation Complete"
    echo "============================================"
    ;;
  *)
    echo "Usage: $0 {test|break|restore|full}"
    echo ""
    echo "  test    - Check which origin is currently serving"
    echo "  break   - Simulate S3 failure, verify Azure failover"
    echo "  restore - Restore S3 access, verify primary recovery"
    echo "  full    - Run complete DR failover cycle"
    exit 1
    ;;
esac
