variable "bucket_name" {
  description = "MinIO bucket name"
  type        = string
}

variable "app_name" {
  description = "Application name (used for IAM user and policy names)"
  type        = string
}

variable "versioning" {
  description = "Enable object versioning"
  type        = bool
  default     = false
}

variable "public" {
  description = "Make bucket publicly readable"
  type        = bool
  default     = false
}
