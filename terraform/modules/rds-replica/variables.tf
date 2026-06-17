variable "project" {
  type = string
}

variable "region_alias" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "k3s_security_group_id" {
  type = string
}

variable "primary_db_instance_arn" {
  description = "Full ARN of the primary RDS instance to replicate from"
  type        = string
}
