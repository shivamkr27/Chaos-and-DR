module "vpc" {
  source       = "../modules/vpc"
  project      = var.project
  region_alias = "dr"
  # Different CIDR so VPCs can be peered later without overlap
  vpc_cidr     = "10.1.0.0/16"
}

# RDS replica disabled — RDS cross-region replication requires backup retention >0 on primary
# and a specific source ARN format; skipping for free-tier demo (DR node still serves traffic)
# module "rds_replica" { ... }

module "k3s" {
  source           = "../modules/k3s"
  project          = var.project
  region_alias     = "dr"
  aws_region       = var.aws_region
  vpc_id           = module.vpc.vpc_id
  subnet_id        = module.vpc.public_subnet_ids[0]
  ssh_public_key   = var.ssh_public_key
  db_host          = "primary.chaos-dr.internal"
  db_password      = var.db_password
  app_image        = var.app_image
  allowed_ssh_cidr = var.allowed_ssh_cidr
}
