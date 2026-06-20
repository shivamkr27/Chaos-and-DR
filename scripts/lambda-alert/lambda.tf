# Terraform for the failover-alert Lambda + SNS topic + Function URL
# Deploy steps:
#   1. zip function.zip index.js
#   2. terraform init && terraform apply
#   3. Copy lambda_url output → workers/wrangler.toml LAMBDA_URL

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "alert_email" {
  description = "Email address to receive failover alerts"
  type        = string
}

variable "alert_secret" {
  description = "Shared secret for Cloudflare Worker → Lambda auth (set same value in wrangler.toml)"
  type        = string
  sensitive   = true
}

# SNS topic + email subscription
resource "aws_sns_topic" "failover" {
  name = "chaos-dr-failover-alert"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.failover.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Lambda execution role
resource "aws_iam_role" "lambda" {
  name = "chaos-dr-lambda-alert-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "sns_publish" {
  name = "chaos-dr-lambda-sns"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = aws_sns_topic.failover.arn
    }]
  })
}

# Lambda function (zip must be built first: zip function.zip index.js)
resource "aws_lambda_function" "alert" {
  function_name = "chaos-dr-failover-alert"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  filename      = "${path.module}/function.zip"

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.failover.arn
      ALERT_SECRET  = var.alert_secret
    }
  }
}

# Public Function URL — no API Gateway needed
resource "aws_lambda_function_url" "alert" {
  function_name      = aws_lambda_function.alert.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["https://chaos-dr-failove.shivamkumarbxr8.workers.dev"]
    allow_methods = ["POST"]
  }
}

output "lambda_url" {
  description = "Paste this into workers/wrangler.toml as LAMBDA_URL"
  value       = aws_lambda_function_url.alert.function_url
}

output "sns_topic_arn" {
  value = aws_sns_topic.failover.arn
}
