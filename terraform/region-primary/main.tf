module "vpc" {
  source       = "../modules/vpc"
  project      = var.project
  region_alias = "primary"
  vpc_cidr     = "10.0.0.0/16"
}

module "rds" {
  source                = "../modules/rds"
  project               = var.project
  region_alias          = "primary"
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  k3s_security_group_id = module.k3s.security_group_id
  db_password           = var.db_password
}

module "k3s" {
  source           = "../modules/k3s"
  project          = var.project
  region_alias     = "primary"
  aws_region       = var.aws_region
  vpc_id           = module.vpc.vpc_id
  subnet_id        = module.vpc.public_subnet_ids[0]
  ssh_public_key   = var.ssh_public_key
  db_host          = module.rds.endpoint
  db_password      = var.db_password
  app_image        = var.app_image
  allowed_ssh_cidr = var.allowed_ssh_cidr
}
