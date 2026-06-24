variable "project_name" {
  type    = string
  default = "multicloud-cdn"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "azure_blob_endpoint" {
  description = "Azure Blob Storage endpoint (leave empty to skip failover origin)"
  type        = string
  default     = ""
}

variable "azure_container_name" {
  description = "Azure Blob container name"
  type        = string
  default     = "cdn-assets"
}
