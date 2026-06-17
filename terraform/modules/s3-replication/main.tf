# IAM role that S3 uses to replicate objects cross-region
resource "aws_iam_role" "replication" {
  name = "${var.project}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "replication" {
  name = "${var.project}-s3-replication-policy"
  role = aws_iam_role.replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = [aws_s3_bucket.primary.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = ["${aws_s3_bucket.primary.arn}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = ["${aws_s3_bucket.dr.arn}/*"]
      }
    ]
  })
}

# Primary bucket (us-east-1)
resource "aws_s3_bucket" "primary" {
  # bucket names must be globally unique
  bucket = "${var.project}-storage-primary-${var.account_id}"

  tags = {
    Name    = "${var.project}-storage-primary"
    Project = var.project
  }
}

resource "aws_s3_bucket_versioning" "primary" {
  bucket = aws_s3_bucket.primary.id
  versioning_configuration {
    # Versioning is required for cross-region replication
    status = "Enabled"
  }
}

resource "aws_s3_bucket_replication_configuration" "primary_to_dr" {
  # Must set versioning first
  depends_on = [aws_s3_bucket_versioning.primary]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.primary.id

  rule {
    id     = "replicate-all-to-dr"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.dr.arn
      storage_class = "STANDARD"
    }
  }
}

# DR bucket (us-west-2) — must be a separate provider alias
resource "aws_s3_bucket" "dr" {
  provider = aws.dr
  bucket   = "${var.project}-storage-dr-${var.account_id}"

  tags = {
    Name    = "${var.project}-storage-dr"
    Project = var.project
  }
}

resource "aws_s3_bucket_versioning" "dr" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Block public access on both buckets
resource "aws_s3_bucket_public_access_block" "primary" {
  bucket                  = aws_s3_bucket.primary.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "dr" {
  provider                = aws.dr
  bucket                  = aws_s3_bucket.dr.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
