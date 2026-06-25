# Multicloud CDN with AWS DevOps Agent

Troubleshoot a multicloud CDN distribution using AWS DevOps Agent — a frontier AI agent for autonomous incident investigation across AWS and Azure.

![Architecture](docs/architecture.png)

## Technology Stack

| Category | Technology | Purpose |
|----------|-----------|---------|
| **OS Platform** | Linux Ubuntu on WSL | Development environment |
| **AI Development** | Kiro CLI (AI Agent) | IaC code generation, architecture design, and troubleshooting |
| **Infrastructure as Code** | Terraform | Multicloud resource provisioning |
| **CDN** | Amazon CloudFront | Global content delivery with edge caching |
| **Primary Origin** | Amazon S3 | Object storage for static assets |
| **Failover Origin** | Azure Blob Storage (GRS) | Cross-cloud redundancy |
| **Monitoring** | Amazon CloudWatch | Metrics, alarms, and observability |
| **Notifications** | Amazon SNS | Alert routing to email/integrations |
| **AI Operations** | AWS DevOps Agent | Autonomous incident investigation and remediation |
| **Identity Federation** | AWS IAM + Azure Entra ID (OIDC) | Cross-cloud authentication for DevOps Agent |
| **CLI Tools** | AWS CLI, Azure CLI, GitHub CLI | Deployment and automation |
| **Scripting** | Bash | Chaos testing and DR simulation |

---

## Architecture

```
┌─────────┐       ┌──────────────────────────┐
│  Users  │──────▶│  CloudFront CDN          │
└─────────┘       └────────────┬─────────────┘
                               │
                      Origin Failover Group
                    (403, 404, 500-504 triggers)
                               │
                ┌──────────────┼──────────────┐
                ▼                             ▼
    ┌────────────────────┐     ┌──────────────────────────┐
    │  AWS S3 (Primary)  │     │ Azure Blob (Failover)    │
    └────────────────────┘     └──────────────────────────┘
                               │
              ┌────────────────▼────────────────┐
              │       AWS DevOps Agent          │
              │  • Autonomous investigation     │
              │  • Cross-cloud root cause       │
              │  • Proactive recommendations    │
              └─────────────────────────────────┘
```

**How it works:**
- CloudFront serves content from S3 (primary) with automatic failover to Azure Blob Storage
- CloudWatch alarms monitor error rates and latency
- AWS DevOps Agent detects alarms, investigates across both clouds, identifies root cause, and recommends fixes

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured (`aws configure`)
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) authenticated (`az login`)
- AWS account with DevOps Agent access (included with AWS Support plans)
- Azure subscription

---

## Step 1: Deploy Azure Infrastructure (Failover Origin)

Deploy the Azure Blob Storage that serves as the failover origin.

```bash
cd terraform/azure
terraform init
terraform apply
```

Note the output:

```
blob_endpoint    = "multicloudcdndev.blob.core.windows.net"
container_name   = "cdn-assets"
```

> **Note:** If you get a provider registration error, the `skip_provider_registration = true` setting in the provider block handles this for accounts without registration permissions.

---

## Step 2: Deploy AWS Infrastructure (Primary Origin + CDN)

Deploy S3, CloudFront, and CloudWatch alarms.

```bash
cd terraform/aws
terraform init
terraform apply \
  -var="azure_blob_endpoint=<BLOB_ENDPOINT_FROM_STEP_1>" \
  -var="alert_email=your@email.com"
```

This creates:
- S3 bucket with Origin Access Control (OAC)
- CloudFront distribution with origin failover group
- CloudWatch alarms (5xx, TotalErrorRate, latency, cache hit rate)
- SNS topic for email notifications

**Confirm the SNS subscription** — check your email and click the confirmation link.

---

## Step 3: Verify the CDN

```bash
curl -s https://<CLOUDFRONT_DOMAIN>/index.html
```

Expected output:
```html
<html><body><h1>Primary Origin (AWS S3)</h1></body></html>
```

---

## Step 4: Set Up AWS DevOps Agent

### 4.1 Create an Agent Space

1. Go to **AWS Console** → **DevOps Agent** (must be in `us-east-1`)
2. Click **Create Agent Space**
3. Name: `multicloud-cdn`
4. Create IAM roles (console guides you)
5. Enable the **Web App**

### 4.2 Connect Azure Tenant

AWS DevOps Agent uses OIDC federation to investigate Azure resources.

**In AWS:**
1. Go to **IAM → Account settings → Outbound Identity Federation** → Enable
2. Copy the **Token Issuer URL**

**In Azure Portal:**
1. Go to **Microsoft Entra ID → App registrations → New registration**
   - Name: `DevOps Agent`
   - Account type: **Single tenant only**
2. Go to **Certificates & secrets → Federated credentials → Add credential**
   - Scenario: **Other issuer**
   - Issuer URL: your AWS Token Issuer URL
   - Subject identifier: the IAM role ARN (check with `aws devops-agent list-services`)
   - Audience: `api://AzureADTokenExchange`
3. Go to **API permissions → Add permission → Azure Service Management → user_impersonation → Grant admin consent**

**Grant subscription access:**

```bash
# Get service principal ID
az ad sp list --filter "appId eq '<APP_CLIENT_ID>'" --query "[].id" -o tsv

# Assign Reader role
az role assignment create \
  --assignee-object-id <SP_OBJECT_ID> \
  --assignee-principal-type ServicePrincipal \
  --role Reader \
  --scope /subscriptions/<SUBSCRIPTION_ID>
```

**Associate Azure with the Agent Space:**

```bash
# Find the Azure service ID
aws devops-agent list-services --region us-east-1

# Create the association
aws devops-agent associate-service \
  --agent-space-id <AGENT_SPACE_ID> \
  --service-id <AZURE_SERVICE_ID> \
  --configuration '{"azure":{"subscriptionId":"<SUBSCRIPTION_ID>"}}' \
  --region us-east-1
```

> **Important:** The console registration may not automatically create the agent space association. The CLI `associate-service` command is required to link the Azure subscription.

---

## Step 5: Test DR Failover

### Single origin failure (S3 down → Azure serves)

```bash
./simulate-failover.sh test      # Verify primary is serving
./simulate-failover.sh break     # Block S3, verify Azure takes over
./simulate-failover.sh restore   # Restore S3
./simulate-failover.sh full      # Run complete cycle
```

### Total outage (both origins down)

```bash
./simulate-total-outage.sh break-all    # Block both origins
./simulate-total-outage.sh status       # Check alarm states
./simulate-total-outage.sh restore-all  # Restore everything
```

### Monitor failover in real time

```bash
while true; do
  curl -s https://<CLOUDFRONT_DOMAIN>/index.html \
    | grep -oE "Primary Origin \(AWS S3\)|Failover Origin \(Azure Blob Storage\)"
  sleep 2
done
```

---

## Step 6: Trigger DevOps Agent Investigation

**Option A: Wait for natural alarm** (5-10 min for CloudFront metrics to propagate)

**Option B: Force alarm state** (immediate, for testing):

```bash
aws cloudwatch set-alarm-state \
  --alarm-name "multicloud-cdn-5xx-error-rate" \
  --state-value ALARM \
  --state-reason "Simulated CDN outage" \
  --region us-east-1
```

**What DevOps Agent does:**
1. Detects the CloudWatch alarm
2. Investigates CloudFront distribution health
3. Identifies S3 origin access denied (bucket policy change)
4. Checks Azure Blob Storage status via tenant connection
5. Provides root cause analysis and mitigation steps
6. Posts findings to Slack/ServiceNow (if configured)

---

## Project Structure

```
├── README.md
├── terraform/
│   ├── aws/
│   │   ├── main.tf           # AWS provider
│   │   ├── variables.tf      # Input variables
│   │   ├── s3.tf             # S3 bucket + OAC
│   │   ├── cloudfront.tf     # Distribution with failover group
│   │   ├── cloudwatch.tf     # Alarms + SNS topic
│   │   └── outputs.tf        # CDN URL, distribution ID
│   └── azure/
│       ├── main.tf           # Azure provider
│       ├── variables.tf      # Input variables
│       ├── storage.tf        # Blob Storage + container
│       └── outputs.tf        # Blob endpoint
├── simulate-failover.sh      # Single origin failover test
├── simulate-total-outage.sh  # Total outage simulation
└── MEDIUM_ARTICLE_SNIPPETS.md
```

---

## Lessons Learned

| # | Lesson | Details |
|---|--------|---------|
| 1 | Include 403 in failover criteria | S3 access denied returns 403, not 500. Without it, CloudFront passes the error through. |
| 2 | Use `TotalErrorRate` alarm | Catches 4xx errors that bypass the 5xx-only alarm. |
| 3 | Use `extended_statistic` for percentiles | The `statistic` field only supports Average, Sum, Min, Max, SampleCount. |
| 4 | CloudFront metrics are delayed 5-10 min | Use `set-alarm-state` for chaos testing. In production, traffic generates metrics naturally. |
| 5 | Azure federation requires explicit association | Console registration alone may not link the subscription to the agent space. Use CLI. |
| 6 | Use `skip_provider_registration = true` | For azurerm 3.x when your account lacks provider registration permissions. |
| 7 | DevOps Agent runs in us-east-1 | But monitors resources in any region and across clouds. |

---

## Cleanup

```bash
# Destroy AWS resources
cd terraform/aws
terraform destroy -var="azure_blob_endpoint=<endpoint>" -var="alert_email=<email>"

# Destroy Azure resources
cd terraform/azure
terraform destroy

# Remove DevOps Agent space (optional)
aws devops-agent delete-agent-space --agent-space-id <ID> --region us-east-1
```

---

## Cost Estimate

| Environment | Monthly Cost |
|-------------|-------------|
| Dev/Test (< 1GB transfer) | ~$1–3 |
| Moderate (10GB, 1M requests) | ~$5–10 |
| Production (100GB, 10M requests) | ~$30–50 |

DevOps Agent is included with AWS Support plans (2-month free trial for new customers).

---

## References

- [AWS DevOps Agent](https://aws.amazon.com/devops-agent/)
- [AWS DevOps Agent GA Announcement](https://aws.amazon.com/about-aws/whats-new/2026/03/aws-devops-agent-generally-available/)
- [CloudFront Origin Failover](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/high_availability_origin_failover.html)
- [Azure Blob Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/)

---

## License

MIT
