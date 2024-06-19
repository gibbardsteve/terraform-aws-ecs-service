variable "app_name" {
  description = "Application name"
  type        = string
  default     = "sdp"
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "aws_access_key_id" {
  description = "AWS Access Key ID"
  type        = string
}

variable "aws_secret_access_key" {
  description = "AWS Secret Access Key"
  type        = string
}

variable "container_image" {
  description = "Container image"
  type        = string
  default     = "github-audit"
}

variable "container_tag" {
  description = "Container tag"
  type        = string
  default     = "v0.0.1"

}

variable "container_port" {
  description = "Container port"
  type        = number
  default     = 5000
}

variable "from_port" {
  description = "From port"
  type        = number
  default     = 5000
}

variable "domain" {
  description = "Domain"
  type        = string
  default     = "sdp-sandbox"
}

variable "domain_extension" {
  description = "Domain extension"
  type        = string
  default     = "aws.onsdigital.uk"
}

variable "service_subdomain" {
  description = "Service subdomain"
  type        = string
  default     = "github-audit"
}

variable "service_cpu" {
  description = "Service CPU"
  type        = string
  default     = "1024"
}

variable "service_memory" {
  description = "Service memory"
  type        = string
  default     = "3072"
}

variable "task_count" {
  description = "Number of instances of the service to run"
  type        = number
  default     = 1
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "log_retention_days" {
  description = "Log retention days"
  type        = number
  default     = 90
}

variable "github_org" {
  description = "Github Organisation"
  type        = string
  default     = "ONS-Innovation"
}


locals {
  url = "${var.domain}.${var.domain_extension}"
}