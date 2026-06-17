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
  description = "SG of the K3s node — only it can reach RDS"
  type        = string
}

variable "db_password" {
  type      = string
  sensitive = true
}
