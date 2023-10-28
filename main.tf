terraform {
  backend "local" {}
}

variable "access_key" {
  type = string
}

variable "secret_key" {
  type = string
}

provider "aws" {
  region     = "ap-northeast-1"
  access_key = var.access_key
  secret_key = var.secret_key

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3     = "http://localhost:4566"
    sqs    = "http://localhost:4566"
    lambda = "http://localhost:4566"
    iam    = "http://localhost:4566"
  }
}

resource "random_string" "bucket_name_suffix" {
  length  = 10
  special = false
  upper   = false
}

resource "aws_s3_bucket" "test_bucket" {
  bucket = "test-bucket-${random_string.bucket_name_suffix.result}"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.test_bucket.id

  queue {
    queue_arn     = aws_sqs_queue.test_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".csv"
  }
}

resource "aws_sqs_queue" "test_queue" {
  name = "test-queue"
}

resource "aws_iam_policy" "test_policy" {
  name        = "sqs-s3-send-event-policy"
  description = "allow send message by s3 create event"
  policy      = data.aws_iam_policy_document.sqs_policy_document.json
}

data "aws_iam_policy_document" "sqs_policy_document" {
  statement {
    sid    = "AllowSQSSendMessage"
    effect = "Allow"
    principals {
      type        = "service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.test_queue.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"

      values = [
        aws_s3_bucket.test_bucket.arn,
      ]
    }
  }
}
