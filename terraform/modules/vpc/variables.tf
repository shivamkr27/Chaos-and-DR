variable "project" {
  description = "Project name used in resource tags and names"
  type        = string
}

variable "region_alias" {
  description = "Short alias for the region, e.g. primary or dr"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
