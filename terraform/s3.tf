# terraform/s3.tf

# Use a random name to ensure the S3 bucket is globally unique
resource "random_pet" "bucket_name" {
  length = 2
}

# --- IAM Role for S3 Replication ---
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
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [aws_s3_bucket.primary_data.arn]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Effect   = "Allow"
        Resource = ["${aws_s3_bucket.primary_data.arn}/*"]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
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


resource "aws_s3_bucket_versioning" "primary_versioning" {
  provider = aws.primary
  bucket = aws_s3_bucket.primary_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "dr_versioning" {
  provider = aws.dr
  bucket = aws_s3_bucket.dr_data.id
  versioning_configuration {
    status = "Enabled"
  }
}


# --- The Replication Configuration ---
resource "aws_s3_bucket_replication_configuration" "primary_replication" {
  provider = aws.primary
  # This depends_on ensures versioning is enabled before the rule is created
  depends_on = [
    aws_s3_bucket_versioning.primary_versioning,
    aws_s3_bucket_versioning.dr_versioning
  ]

  bucket = aws_s3_bucket.primary_data.id
  role   = aws_iam_role.s3_replication_role.arn

  rule {
    id = "replicate-all"
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