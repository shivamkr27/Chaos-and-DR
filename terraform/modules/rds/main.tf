resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.region_alias}-rds-sg"
  description = "Allow PostgreSQL from K3s nodes only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.k3s_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-${var.region_alias}-rds-sg"
    Project = var.project
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.region_alias}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name    = "${var.project}-${var.region_alias}-db-subnet-group"
    Project = var.project
  }
}

resource "aws_db_instance" "postgres" {
  identifier        = "${var.project}-${var.region_alias}-postgres"
  engine            = "postgres"
  engine_version    = "15.7"
  instance_class    = "db.t3.micro"  # free tier eligible
  allocated_storage = 20             # GB, free tier max

  db_name  = "chaosdb"
  username = "postgres"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  storage_encrypted      = true

  # Free tier: single-AZ, no multi-AZ
  multi_az               = false
  publicly_accessible    = false
  skip_final_snapshot    = true   # ok for dev/demo
  deletion_protection    = false

  # Enable automated backups (needed for cross-region replica later)
  backup_retention_period = 1
  backup_window           = "03:00-04:00"

  tags = {
    Name      = "${var.project}-${var.region_alias}-postgres"
    Project   = var.project
    ManagedBy = "terraform"
  }
}
