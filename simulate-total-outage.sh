#!/bin/bash
# simulate-total-outage.sh - Break BOTH origins to trigger DevOps Agent investigation
# This creates a full CDN outage that DevOps Agent should detect, investigate, and recommend fixes

set -e

BUCKET="multicloud-cdn-origin-dev"
CDN_URL="https://d26pi2qd1jbbi9.cloudfront.net/index.html"
DISTRIBUTION_ID="E1KBTHXXT7BIIW"
STORAGE_ACCOUNT="multicloudcdndev"
CONTAINER="cdn-assets"
DIST_ARN="arn:aws:cloudfront::977901218063:distribution/E1KBTHXXT7BIIW"

echo "============================================"
echo "  TOTAL CDN OUTAGE SIMULATION"
echo "  Both origins will be disabled"
echo "============================================"
echo ""

case "${1:-}" in
  break-all)
    echo "[CHAOS] Step 1: Denying CloudFront access to S3..."
    aws s3api put-bucket-policy --bucket "$BUCKET" --policy '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Deny",
        "Principal": "*",
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::'"$BUCKET"'/*"
      }]
    }'
    echo "       ✅ S3 origin blocked"

    echo ""
    echo "[CHAOS] Step 2: Disabling Azure Blob public access..."
    az storage container set-permission --name "$CONTAINER" --account-name "$STORAGE_ACCOUNT" --public-access off
    echo "       ✅ Azure origin blocked"

    echo ""
    echo "[CHAOS] Step 3: Invalidating CloudFront cache..."
    aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths "/*" > /dev/null
    echo "       ✅ Cache invalidated"

    echo ""
    echo "[WAIT] Waiting 30s for propagation..."
    sleep 30

    echo ""
    echo "[TEST] Requesting $CDN_URL ..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$CDN_URL")
    echo "       HTTP Status: $HTTP_CODE"
    echo ""
    if [ "$HTTP_CODE" -ge 400 ]; then
      echo "🔥 TOTAL OUTAGE CONFIRMED - Both origins are down"
      echo ""
      echo "DevOps Agent should now:"
      echo "  1. Detect 5xx/4xx CloudWatch alarm firing"
      echo "  2. Auto-investigate the incident"
      echo "  3. Identify both origins are unreachable"
      echo "  4. Provide root cause: S3 policy denial + Azure access disabled"
      echo "  5. Recommend remediation steps"
    fi
    ;;

  restore-all)
    echo "[RESTORE] Step 1: Restoring S3 bucket policy..."
    aws s3api put-bucket-policy --bucket "$BUCKET" --policy '{
      "Version": "2012-10-17",
      "Statement": [{
        "Sid": "AllowCloudFrontOAC",
        "Effect": "Allow",
        "Principal": {"Service": "cloudfront.amazonaws.com"},
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::'"$BUCKET"'/*",
        "Condition": {
          "StringEquals": {
            "AWS:SourceArn": "'"$DIST_ARN"'"
          }
        }
      }]
    }'
    echo "       ✅ S3 origin restored"

    echo ""
    echo "[RESTORE] Step 2: Restoring Azure Blob public access..."
    az storage container set-permission --name "$CONTAINER" --account-name "$STORAGE_ACCOUNT" --public-access blob
    echo "       ✅ Azure origin restored"

    echo ""
    echo "[WAIT] Waiting 15s..."
    sleep 15

    echo ""
    echo "[TEST] Verifying CDN is back..."
    RESPONSE=$(curl -s "$CDN_URL")
    echo "       Response: $RESPONSE"
    if echo "$RESPONSE" | grep -q "Primary Origin\|Failover Origin"; then
      echo ""
      echo "✅ CDN RESTORED SUCCESSFULLY"
    else
      echo ""
      echo "⚠️  CDN still returning errors - may need more time for cache propagation"
    fi
    ;;

  status)
    echo "[STATUS] Checking CDN health..."
    echo ""
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$CDN_URL")
    RESPONSE=$(curl -s "$CDN_URL" 2>/dev/null | head -1)
    echo "  HTTP Code: $HTTP_CODE"
    echo "  Response:  $RESPONSE"
    echo ""

    echo "[STATUS] Checking CloudWatch alarm states..."
    aws cloudwatch describe-alarms --alarm-name-prefix "multicloud-cdn" --query "MetricAlarms[].{Name:AlarmName,State:StateValue}" --output table --region us-east-1
    ;;

  *)
    echo "Usage: $0 {break-all|restore-all|status}"
    echo ""
    echo "  break-all   - Disable BOTH origins (total outage)"
    echo "  restore-all - Restore both origins"
    echo "  status      - Check CDN health and alarm states"
    exit 1
    ;;
esac
