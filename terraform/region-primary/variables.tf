variable "project" {
  type    = string
  default = "chaos-dr"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "ssh_public_key" {
  description = "Contents of your ~/.ssh/id_rsa.pub"
  type        = string
}

variable "app_image" {
  description = "Docker image pushed to ECR or Docker Hub"
  type        = string
  default     = "your-dockerhub-username/chaos-dr-app:latest"
}
