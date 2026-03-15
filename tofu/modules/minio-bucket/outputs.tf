output "bucket_name" {
  description = "The created bucket name"
  value       = minio_s3_bucket.this.bucket
}

output "access_key" {
  description = "Service account access key for the app"
  value       = minio_iam_service_account.app_sa.access_key
  sensitive   = true
}

output "secret_key" {
  description = "Service account secret key for the app"
  value       = minio_iam_service_account.app_sa.secret_key
  sensitive   = true
}

output "endpoint" {
  description = "MinIO S3-compatible endpoint URL"
  value       = "http://minio.minio.svc.cluster.local:9000"
}
