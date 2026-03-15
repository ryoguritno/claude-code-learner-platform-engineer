output "stream_name" {
  description = "The created NATS stream name"
  value       = jetstream_stream.this.name
}

output "subjects" {
  description = "Subjects captured by this stream"
  value       = jetstream_stream.this.subjects
}

output "nats_url" {
  description = "NATS connection URL (in-cluster)"
  value       = "nats://nats.nats.svc.cluster.local:4222"
}
