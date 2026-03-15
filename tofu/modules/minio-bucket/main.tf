# minio-bucket module
# Creates an S3-compatible bucket in MinIO

terraform {
  required_providers {
    minio = {
      source  = "aminueza/minio"
      version = "~> 2.0"
    }
  }
}

resource "minio_s3_bucket" "this" {
  bucket = var.bucket_name
  acl    = var.public ? "public" : "private"
}

resource "minio_s3_bucket_versioning" "this" {
  count  = var.versioning ? 1 : 0
  bucket = minio_s3_bucket.this.bucket

  versioning_configuration {
    status = "Enabled"
  }
}

# Create a dedicated policy for the app to access this bucket
resource "minio_iam_policy" "bucket_access" {
  name = "${var.app_name}-bucket-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/*",
        ]
      }
    ]
  })
}

# Service user for programmatic access
resource "minio_iam_user" "app_user" {
  name          = "${var.app_name}-minio-user"
  force_destroy = true
}

resource "minio_iam_user_policy_attachment" "app_access" {
  user_name   = minio_iam_user.app_user.name
  policy_name = minio_iam_policy.bucket_access.name
}

resource "minio_iam_service_account" "app_sa" {
  target_user = minio_iam_user.app_user.name
}
