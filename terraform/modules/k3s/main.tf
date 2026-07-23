# Security group for K3s node
resource "aws_security_group" "k3s" {
  name        = "${var.project}-${var.region_alias}-k3s-sg"
  description = "K3s node traffic"
  vpc_id      = var.vpc_id

  # SSH access — set allowed_ssh_cidr in tfvars to restrict (e.g. "1.2.3.4/32")
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # App HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # App HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NodePort range (K8s services exposed via NodePort)
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus scraping between regions (optional)
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-${var.region_alias}-k3s-sg"
    Project = var.project
  }
}

# Latest Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "k3s" {
  key_name   = "${var.project}-${var.region_alias}-key"
  public_key = var.ssh_public_key
}

resource "aws_instance" "k3s" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"   # free tier on new accounts
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.k3s.id]
  key_name               = aws_key_pair.k3s.key_name
  iam_instance_profile   = aws_iam_instance_profile.k3s_node.name

  root_block_device {
    volume_size = 30  # GB minimum for AL2023 AMI snapshot
    volume_type = "gp3"
  }

  user_data_replace_on_change = true   # replace instance when bootstrap script changes

  # Bootstrap K3s + Docker + required tools on first boot
  user_data = templatefile("${path.module}/userdata.sh.tpl", {
    region      = var.aws_region
    project     = var.project
    db_host     = var.db_host
    db_password = var.db_password
    api_key     = var.api_key
    app_image   = var.app_image
  })

  tags = {
    Name        = "${var.project}-${var.region_alias}-k3s-node"
    Project     = var.project
    Region      = var.region_alias
    ManagedBy   = "terraform"
  }
}

# Elastic IP so the public IP doesn't change on restart
resource "aws_eip" "k3s" {
  instance = aws_instance.k3s.id
  domain   = "vpc"

  tags = {
    Name    = "${var.project}-${var.region_alias}-eip"
    Project = var.project
  }
}
