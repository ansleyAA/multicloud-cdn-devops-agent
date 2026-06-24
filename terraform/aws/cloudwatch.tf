# SNS topic for alarm notifications
resource "aws_sns_topic" "cdn_alerts" {
  name = "${var.project_name}-cdn-alerts"
}

variable "alert_email" {
  description = "Email for CloudWatch alarm notifications (optional)"
  type        = string
  default     = ""
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.cdn_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "error_rate_5xx" {
  alarm_name          = "${var.project_name}-5xx-error-rate"
  alarm_description   = "CloudFront 5xx error rate exceeds threshold"
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

resource "aws_cloudwatch_metric_alarm" "error_rate_total" {
  alarm_name          = "${var.project_name}-total-error-rate"
  alarm_description   = "CloudFront total error rate (4xx+5xx) exceeds threshold"
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

resource "aws_cloudwatch_metric_alarm" "origin_latency" {
  alarm_name          = "${var.project_name}-origin-latency"
  alarm_description   = "Origin latency exceeds threshold"
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

resource "aws_cloudwatch_metric_alarm" "cache_hit_rate" {
  alarm_name          = "${var.project_name}-low-cache-hit-rate"
  alarm_description   = "Cache hit rate dropped below threshold"
  namespace           = "AWS/CloudFront"
  metric_name         = "CacheHitRate"
  statistic           = "Average"
  period              = 900
  evaluation_periods  = 2
  threshold           = 50
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.cdn_alerts.arn]

  dimensions = {
    DistributionId = aws_cloudfront_distribution.cdn.id
    Region         = "Global"
  }
}
