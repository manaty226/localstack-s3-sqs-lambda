terraform {
  backend "local" {}
}

variable "access_key" {
  type = string
}

variable "secret_key" {
  type = string
}

# LocalStackへデプロイするためのプロバイダ設定
provider "aws" {
  region     = "ap-northeast-1"
  access_key = var.access_key
  secret_key = var.secret_key

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # 利用するサービス分だけLocalStackのコンテナが露出しているエンドポイントを指定する
  endpoints {
    s3     = "http://localhost:4566"
    sqs    = "http://localhost:4566"
    lambda = "http://localhost:4566"
    iam    = "http://localhost:4566"
  }
}

###################################################
# S3バケットの設定
# バケットを作成し通知設定としてSQSを指定する
###################################################
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

###################################################
# SQSの設定
# S3からの通知を受け付けるIAMポリシーを作成する
###################################################
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

###################################################
# Lambdaの設定
# SQSをトリガーにしてS3からの通知を受け付ける
# terraformのlocal-execでLambdaをビルドしてデプロイする
###################################################
resource "aws_lambda_function" "function" {
  function_name = "s3-provoked-sqs-lambda"
  description   = "A sample lambda function triggered by s3 event via sqs"
  role          = aws_iam_role.lambda.arn
  handler       = "handler"
  memory_size   = 128

  filename         = local.archive_path
  source_code_hash = data.archive_file.function_archive.output_base64sha256

  runtime = "provided.al2"
}

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn  = aws_sqs_queue.test_queue.arn
  function_name     = aws_lambda_function.function.arn
  batch_size        = 1
  starting_position = "LATEST"
}

locals {
  src_path = "handler.go"
  # binary file must be named bootstrap
  binary_path  = "build/bootstrap"
  archive_path = "./lambda/build/handler.zip"
}

resource "null_resource" "function_binary" {
  provisioner "local-exec" {
    command = "cd lambda && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 GOFLAGS=-trimpath go build -mod=readonly -ldflags='-s -w' -o ${local.binary_path} ${local.src_path}"
  }
}

data "archive_file" "function_archive" {
  depends_on = [null_resource.function_binary]

  type        = "zip"
  source_file = "./lambda/${local.binary_path}"
  output_path = local.archive_path
}

data "aws_iam_policy_document" "assume_lambda_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "lambda" {
  name               = "AssumeLambdaRole"
  description        = "Role for lambda to assume lambda"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda_role.json
}
