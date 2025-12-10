# terraform/s3.tf

# Use a random name to ensure all S3 buckets are globally unique
resource "random_pet" "bucket_name" {
  length = 2
}

# ===================================================================
# --- Section 1: Application Data & Disaster Recovery Buckets ---
# ===================================================================

# --- IAM Role for S3 Cross-Region Replication ---
# This role grants S3 the permission to replicate objects on your behalf.
resource "aws_iam_role" "s3_replication_role" {
  provider = aws.primary
  name     = "s3-replication-role-${random_pet.bucket_name.id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "s3_replication_policy" {
  provider = aws.primary
  name     = "s3-replication-policy-${random_pet.bucket_name.id}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Effect   = "Allow"
        Resource = [aws_s3_bucket.primary_data.arn]
      },
      {
        Action   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.primary_data.arn}/*"]
      },
      {
        Action   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.dr_data.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_replication_attach" {
  provider   = aws.primary
  role       = aws_iam_role.s3_replication_role.name
  policy_arn = aws_iam_policy.s3_replication_policy.arn
}

# --- Primary S3 Bucket (in us-east-1) ---
resource "aws_s3_bucket" "primary_data" {
  provider = aws.primary
  bucket   = "primary-data-bucket-${random_pet.bucket_name.id}"
}

# --- DR S3 Bucket (in us-west-2) ---
resource "aws_s3_bucket" "dr_data" {
  provider = aws.dr
  bucket   = "dr-data-bucket-${random_pet.bucket_name.id}"
}

# --- Versioning for Data Buckets ---
resource "aws_s3_bucket_versioning" "primary_versioning" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "dr_versioning" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# --- Security: Block Public Access for Data Buckets ---
resource "aws_s3_bucket_public_access_block" "primary_access_block" {
  provider                = aws.primary
  bucket                  = aws_s3_bucket.primary_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "dr_access_block" {
  provider                = aws.dr
  bucket                  = aws_s3_bucket.dr_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Security: Enforce Server-Side Encryption for Data Buckets ---
resource "aws_s3_bucket_server_side_encryption_configuration" "primary_encryption" {
  provider = aws.primary
  bucket   = aws_s3_bucket.primary_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dr_encryption" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# --- Cost Management: Lifecycle Policy for DR Data Bucket ---
resource "aws_s3_bucket_lifecycle_configuration" "dr_lifecycle" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr_data.id
  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }
    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# --- The Replication Configuration Itself ---
resource "aws_s3_bucket_replication_configuration" "primary_replication" {
  provider   = aws.primary
  depends_on = [aws_s3_bucket_versioning.primary_versioning, aws_s3_bucket_versioning.dr_versioning]
  bucket     = aws_s3_bucket.primary_data.id
  role       = aws_iam_role.s3_replication_role.arn
  rule {
    id     = "replicate-all"
    status = "Enabled"
    destination {
      bucket = aws_s3_bucket.dr_data.arn
    }
    filter {}
    delete_marker_replication {
      status = "Enabled"
    }
  }
}


# ===================================================================
# --- Section 2: Bucket for CI/CD Pipeline Artifacts ---
# ===================================================================

resource "aws_s3_bucket" "codedeploy_artifacts" {
  provider = aws.primary
  bucket   = "codedeploy-artifacts-${random_pet.bucket_name.id}"
}

# --- Security: Block Public Access for Artifacts Bucket ---
resource "aws_s3_bucket_public_access_block" "codedeploy_access_block" {
  provider                = aws.primary
  bucket                  = aws_s3_bucket.codedeploy_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Security: Enable Versioning for Artifacts Bucket ---
resource "aws_s3_bucket_versioning" "codedeploy_versioning" {
  provider = aws.primary
  bucket   = aws_s3_bucket.codedeploy_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# --- Security: Enforce Encryption for Artifacts Bucket ---
resource "aws_s3_bucket_server_side_encryption_configuration" "codedeploy_encryption" {
  provider = aws.primary
  bucket   = aws_s3_bucket.codedeploy_artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# --- Cost Management: Lifecycle Policy to Clean Up Old Artifacts ---
resource "aws_s3_bucket_lifecycle_configuration" "codedeploy_lifecycle" {
  provider = aws.primary
  bucket   = aws_s3_bucket.codedeploy_artifacts.id
  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"
    filter {}
    expiration {
      days = 14 # Permanently delete deployment artifacts after 2 weeks
    }
  }
}

# --- Terraform Output for the CI/CD Pipeline ---
output "codedeploy_artifacts_bucket_name" {
  description = "The name of the S3 bucket for storing CodeDeploy artifacts."
  value       = aws_s3_bucket.codedeploy_artifacts.id
}