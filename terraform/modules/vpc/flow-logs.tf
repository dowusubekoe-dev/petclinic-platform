# VPC flow logs -> dedicated encrypted S3 bucket.
#
# Secure-by-default (enable_flow_logs = true). Flow logs are the primary network
# forensic trail; S3 delivery (vs CloudWatch) keeps cost negligible — a 14-day
# lifecycle on a low-traffic learning cluster is pennies/month. All resources
# are conditional on the toggle so an environment can opt out with a documented
# cost justification.

locals {
  flow_logs_enabled = var.enable_flow_logs
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "flow_logs" {
  #checkov:skip=CKV_AWS_18:This IS the log-delivery bucket; enabling access logging on it would recurse
  #checkov:skip=CKV_AWS_144:Cross-region replication is unwarranted for short-lived (14d) VPC flow logs
  #checkov:skip=CKV2_AWS_62:Event notifications are not needed for flow-log storage
  #checkov:skip=CKV_AWS_145:SSE-S3 (AES256) is sufficient for non-sensitive flow logs; a CMK is avoided for cost
  #checkov:skip=CKV_AWS_21:Versioning IS configured (aws_s3_bucket_versioning.flow_logs); Checkov graph cannot resolve the ref through the count-indexed bucket
  #checkov:skip=CKV2_AWS_6:Public access block IS configured (aws_s3_bucket_public_access_block.flow_logs); count-index graph limitation
  #checkov:skip=CKV2_AWS_61:Lifecycle config IS present (aws_s3_bucket_lifecycle_configuration.flow_logs); count-index graph limitation
  count = local.flow_logs_enabled ? 1 : 0

  bucket        = "${local.name_prefix}-vpc-flow-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc-flow-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  count = local.flow_logs_enabled ? 1 : 0

  bucket                  = aws_s3_bucket.flow_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "flow_logs" {
  count  = local.flow_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  count  = local.flow_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  count  = local.flow_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  rule {
    id     = "expire-flow-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.flow_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.flow_log_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Bucket policy permitting the VPC Flow Logs delivery service to write objects.
resource "aws_s3_bucket_policy" "flow_logs" {
  count  = local.flow_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSLogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.flow_logs[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid       = "AWSLogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = aws_s3_bucket.flow_logs[0].arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      }
    ]
  })
}

resource "aws_flow_log" "vpc" {
  count = local.flow_logs_enabled ? 1 : 0

  vpc_id                   = aws_vpc.main.id
  traffic_type             = "ALL"
  log_destination_type     = "s3"
  log_destination          = aws_s3_bucket.flow_logs[0].arn
  max_aggregation_interval = 600

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc-flow-log"
  })
}
