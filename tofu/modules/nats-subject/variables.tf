variable "stream_name" {
  description = "NATS JetStream stream name (uppercase, underscores)"
  type        = string
}

variable "app_name" {
  description = "Application name (used for descriptions)"
  type        = string
}

variable "subjects" {
  description = "List of NATS subjects to capture in this stream"
  type        = list(string)
}

variable "consumer_names" {
  description = "Names for durable consumers to create"
  type        = list(string)
  default     = []
}

variable "storage_type" {
  description = "Storage type: file or memory"
  type        = string
  default     = "file"
  validation {
    condition     = contains(["file", "memory"], var.storage_type)
    error_message = "Storage type must be file or memory."
  }
}

variable "max_bytes" {
  description = "Maximum bytes for the stream (-1 = unlimited)"
  type        = number
  default     = -1
}

variable "max_age_seconds" {
  description = "Maximum age of messages in seconds (0 = unlimited)"
  type        = number
  default     = 0
}

variable "replicas" {
  description = "Number of stream replicas"
  type        = number
  default     = 1
}
