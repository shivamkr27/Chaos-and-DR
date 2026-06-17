resource "aws_security_group" "rds_replica" {
  name        = "${var.project}-${var.region_alias}-rds-replica-sg"
  description = "Allow PostgreSQL from K3s DR node only"
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
    Name    = "${var.project}-${var.region_alias}-rds-replica-sg"
    Project = var.project
  }
}

resource "aws_db_subnet_group" "replica" {
  name       = "${var.project}-${var.region_alias}-replica-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name    = "${var.project}-${var.region_alias}-replica-subnet-group"
    Project = var.project
  }
}

resource "aws_db_instance" "replica" {
  identifier     = "${var.project}-${var.region_alias}-postgres-replica"
  instance_class = "db.t3.micro"

  # This is what makes it a cross-region replica — points to primary ARN
  replicate_source_db = var.primary_db_instance_arn

  db_subnet_group_name   = aws_db_subnet_group.replica.name
  vpc_security_group_ids = [aws_security_group.rds_replica.id]

  publicly_accessible = false
  skip_final_snapshot = true
  deletion_protection = false

  # Must be false on replica — can't set a password on a replica
  # Password is inherited from primary
  # username and db_name are also inherited

  tags = {
    Name      = "${var.project}-${var.region_alias}-postgres-replica"
    Project   = var.project
    Role      = "replica"
    ManagedBy = "terraform"
  }
}
