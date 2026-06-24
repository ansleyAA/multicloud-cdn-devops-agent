# Code Snippets for Medium Article
# Topic: Troubleshooting a Multicloud CDN with AWS DevOps Agent

---

## Snippet 1: Terraform Providers (AWS + Azure)

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}
```

---

## Snippet 2: S3 Primary Origin with CloudFront OAC

```hcl
resource "aws_s3_bucket" "origin" {
  bucket = "multicloud-cdn-origin"
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "multicloud-cdn-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
```

---

## Snippet 3: Azure Blob Storage Failover Origin

```hcl
resource "azurerm_storage_account" "origin" {
  name                     = "multicloudcdnfailover"
  resource_group_name      = azurerm_resource_group.cdn.name
  location                 = "eastus"
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_container" "cdn" {
  name                  = "cdn-assets"
  storage_account_name  = azurerm_storage_account.origin.name
  container_access_type = "blob"
}
```

---

## Snippet 4: CloudFront Distribution with Origin Failover Group

```hcl
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"

  # Primary origin - AWS S3
  origin {
    domain_name              = aws_s3_bucket.origin.bucket_regional_domain_name
    origin_id                = "s3-primary"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # Failover origin - Azure Blob Storage
  origin {
    domain_name = "${azurerm_storage_account.origin.name}.blob.core.windows.net"
    origin_id   = "azure-failover"
    origin_path = "/${azurerm_storage_container.cdn.name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Origin failover group - includes 403/404 for access denied scenarios
  origin_group {
    origin_id = "multicloud-failover-group"

    failover_criteria {
      status_codes = [403, 404, 500, 502, 503, 504]
    }

    member {
      origin_id = "s3-primary"
    }

    member {
      origin_id = "azure-failover"
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "multicloud-failover-group"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
```

> **Lesson learned:** Include `403` and `404` in failover criteria — not just 5xx. When an S3 bucket policy denies access, it returns 403, not 500. Without 403 in the list, CloudFront passes the error through instead of failing over.

---

## Snippet 5: CloudWatch Alarms for DevOps Agent

```hcl
# SNS topic for alarm notifications
resource "aws_sns_topic" "cdn_alerts" {
  name = "multicloud-cdn-alerts"
}

# 5xx error rate alarm
resource "aws_cloudwatch_metric_alarm" "error_rate_5xx" {
  alarm_name          = "multicloud-cdn-5xx-error-rate"
  alarm_description   = "Triggers DevOps Agent investigation on origin failures"
  namespace           = "AWS/CloudFront"
  metric_name         = "5xxErrorRate"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.cdn_alerts.arn]

  dimensions = {
    DistributionId = aws_cloudfront_distribution.cdn.id
    Region         = "Global"
  }
}

# Total error rate (4xx + 5xx) - catches access denied scenarios
resource "aws_cloudwatch_metric_alarm" "error_rate_total" {
  alarm_name          = "multicloud-cdn-total-error-rate"
  alarm_description   = "Catches 403/404 errors that bypass 5xx alarm"
  namespace           = "AWS/CloudFront"
  metric_name         = "TotalErrorRate"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cdn_alerts.arn]

  dimensions = {
    DistributionId = aws_cloudfront_distribution.cdn.id
    Region         = "Global"
  }
}

# Origin latency
resource "aws_cloudwatch_metric_alarm" "origin_latency" {
  alarm_name          = "multicloud-cdn-origin-latency"
  alarm_description   = "Cross-cloud latency spike detection"
  namespace           = "AWS/CloudFront"
  metric_name         = "OriginLatency"
  extended_statistic  = "p99"
  period              = 300
  evaluation_periods  = 3
  threshold           = 2000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cdn_alerts.arn]

  dimensions = {
    DistributionId = aws_cloudfront_distribution.cdn.id
    Region         = "Global"
  }
}
```

> **Lesson learned:** Use `TotalErrorRate` alongside `5xxErrorRate`. CloudFront metrics have a 5-10 minute delay, and origin access denials show as 4xx not 5xx. Also use `extended_statistic` (not `statistic`) for percentile metrics like p99.

---

## Snippet 6: Azure Federation for DevOps Agent (CLI)

```bash
# 1. Get your Azure tenant ID
az account show --query tenantId -o tsv

# 2. Create App Registration with federated credential
az ad app list --display-name "DevOps Agent" --query "[].{appId:appId, id:id}" -o table

# 3. Verify federated credential
az ad app federated-credential list --id <APP_OBJECT_ID> -o json
# Should show:
#   issuer: https://<account-id>.tokens.sts.global.api.aws
#   subject: arn:aws:iam::<account>:role/service-role/DevOpsAgentRole-AzureWIT-<id>
#   audiences: ["api://AzureADTokenExchange"]

# 4. Grant Reader role on subscription
az role assignment create \
  --assignee-object-id <SP_OBJECT_ID> \
  --assignee-principal-type ServicePrincipal \
  --role Reader \
  --scope /subscriptions/<SUBSCRIPTION_ID>

# 5. Associate Azure with DevOps Agent space
aws devops-agent associate-service \
  --agent-space-id <AGENT_SPACE_ID> \
  --service-id <AZURE_SERVICE_ID> \
  --configuration '{"azure":{"subscriptionId":"<SUBSCRIPTION_ID>"}}' \
  --region us-east-1
```

> **Lesson learned:** The Azure console registration may not create the agent space association automatically. Use `aws devops-agent associate-service` via CLI to explicitly link the subscription. Also ensure the federated credential's subject ARN matches the *actual* WIT role the service registered (check with `aws devops-agent list-services`).

---

## Snippet 7: DR Failover Simulation Script

```bash
#!/bin/bash
# Simulate S3 origin failure → verify Azure failover

BUCKET="multicloud-cdn-origin-dev"
CDN_URL="https://d26pi2qd1jbbi9.cloudfront.net/index.html"
DISTRIBUTION_ID="E1KBTHXXT7BIIW"

echo "--- Before failover ---"
curl -s "$CDN_URL" | grep -oE "Primary Origin|Failover Origin"
# Output: Primary Origin

echo "--- Blocking S3 origin ---"
aws s3api put-bucket-policy --bucket "$BUCKET" --policy '{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::'"$BUCKET"'/*"
  }]
}'

echo "--- Invalidating cache ---"
aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" --paths "/*"
sleep 30

echo "--- After failover ---"
curl -s "$CDN_URL" | grep -oE "Primary Origin|Failover Origin"
# Output: Failover Origin
```

---

## Snippet 8: Total Outage Simulation (Both Origins)

```bash
#!/bin/bash
# Break BOTH origins to trigger DevOps Agent investigation

# Block S3
aws s3api put-bucket-policy --bucket "$BUCKET" --policy '{
  "Version": "2012-10-17",
  "Statement": [{"Effect":"Deny","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::'"$BUCKET"'/*"}]
}'

# Block Azure Blob
az storage container set-permission \
  --name "cdn-assets" \
  --account-name "multicloudcdndev" \
  --public-access off

# Invalidate cache
aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths "/*"

# Force alarm to trigger DevOps Agent
aws cloudwatch set-alarm-state \
  --alarm-name "multicloud-cdn-5xx-error-rate" \
  --state-value ALARM \
  --state-reason "Total CDN outage - both origins blocked" \
  --region us-east-1
```

> **Lesson learned:** CloudFront metrics have a 5-10 minute delay. For immediate DevOps Agent investigation during chaos testing, use `set-alarm-state` to manually trigger the alarm. In production, real traffic generates metrics naturally.

---

## Snippet 9: Monitoring Failover in Real Time

```bash
# Watch origin switch live (Ctrl+C to stop)
while true; do
  curl -s https://d26pi2qd1jbbi9.cloudfront.net/index.html \
    | grep -oE "Primary Origin \(AWS S3\)|Failover Origin \(Azure Blob Storage\)"
  sleep 2
done
```

---

## Snippet 10: Architecture Diagram (ASCII)

```
┌─────────┐       ┌──────────────────────────┐
│  Users  │──────▶│  CloudFront CDN          │
└─────────┘       │  d26pi2qd1jbbi9.cf.net   │
                  └────────────┬─────────────┘
                               │
                      Origin Failover Group
                    (403, 404, 500-504 triggers)
                               │
                ┌──────────────┼──────────────┐
                ▼                             ▼
    ┌────────────────────┐     ┌──────────────────────────┐
    │  AWS S3 (Primary)  │     │ Azure Blob (Failover)    │
    │  multicloud-cdn-   │     │ multicloudcdndev.blob.   │
    │  origin-dev        │     │ core.windows.net         │
    └────────────────────┘     └──────────────────────────┘
                │                             │
                └──────────────┬──────────────┘
                               │
              ┌────────────────▼────────────────┐
              │     AWS DevOps Agent            │
              │                                 │
              │  • Detects alarm (CloudWatch)   │
              │  • Investigates both clouds     │
              │  • Root cause analysis          │
              │  • Recommends remediation       │
              │  • Proactive prevention         │
              └─────────────────────────────────┘
                        │            │
                   AWS Account    Azure Tenant
                   (IAM role)    (OIDC federation)
```

---

## Key Lessons Learned

1. **Include 403 in failover criteria** — S3 access denied returns 403, not 500
2. **Use `TotalErrorRate` alarm** — catches 4xx errors that bypass the 5xx alarm
3. **Use `extended_statistic` for percentiles** — `statistic` only supports Average, Sum, Min, Max, SampleCount
4. **CloudFront metrics are delayed 5-10 min** — use `set-alarm-state` for chaos testing
5. **Azure OIDC federation requires explicit association** — console registration alone may not link the subscription to the agent space
6. **Use `skip_provider_registration = true`** for azurerm 3.x when you lack provider registration permissions
7. **DevOps Agent runs in us-east-1** — but monitors resources in any region/cloud
