variable "project" {
  type = string
}

variable "account_id" {
  description = "AWS account ID — used to make bucket names globally unique"
  type        = string
}

variable "primary_region" {
  type    = string
  default = "us-east-1"
}

variable "dr_region" {
  type    = string
  default = "us-west-2"
}
