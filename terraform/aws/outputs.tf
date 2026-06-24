output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.cdn.id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.origin.id
}

output "cdn_url" {
  value = "https://${aws_cloudfront_distribution.cdn.domain_name}/index.html"
}
