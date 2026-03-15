# nats-subject module
# Creates a NATS JetStream stream with subjects

terraform {
  required_providers {
    jetstream = {
      source  = "nats-io/jetstream"
      version = "~> 0.0.35"
    }
  }
}

resource "jetstream_stream" "this" {
  name        = var.stream_name
  subjects    = var.subjects
  storage     = var.storage_type
  max_bytes   = var.max_bytes
  max_age     = var.max_age_seconds * 1000000000  # Convert to nanoseconds
  replicas    = var.replicas
  description = "Stream for ${var.app_name} — managed by OpenTofu"
}

# Create a durable push consumer for each subject group
resource "jetstream_consumer" "default" {
  for_each = toset(var.consumer_names)

  stream_name    = jetstream_stream.this.name
  durable_name   = each.value
  deliver_all    = true
  ack_policy     = "explicit"
  max_deliver    = 5
  ack_wait       = 30  # seconds
  description    = "Default consumer for ${var.app_name}"
}
