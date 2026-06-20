# IAM instance profile so the K3s EC2 node can call AWS APIs
# without storing credentials in the cluster.
# Used by: region-failure experiment (stop/start EC2), failover script.

resource "aws_iam_role" "k3s_node" {
  name = "${var.project}-${var.region_alias}-k3s-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = var.project
  }
}

resource "aws_iam_role_policy" "k3s_node" {
  name = "${var.project}-${var.region_alias}-k3s-node-policy"
  role = aws_iam_role.k3s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Chaos experiment: stop/start EC2 in primary region
        Sid    = "EC2ChaosControl"
        Effect = "Allow"
        Action = [
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeAddresses"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = var.project
          }
        }
      },
      {
        # Route 53 for failover script — List/Describe require Resource="*" (AWS limitation)
        # ChangeResourceRecordSets is scoped to hosted zones only
        Sid    = "Route53FailoverList"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListHealthChecks",
          "route53:GetHealthCheckStatus"
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53FailoverWrite"
        Effect = "Allow"
        Action = ["route53:ChangeResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/*"
      },
      # RDS promotion removed — rds-replica module is disabled (free-tier demo).
      # Re-add if enabling cross-region RDS replica: rds:PromoteReadReplica, rds:DescribeDBInstances
      {
        # Secrets Manager — DB password for failover script
        Sid    = "SecretAccess"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:*:*:secret:${var.project}/*"
      }
    ]
  })
}

# SSM managed policy — lets us run commands without SSH (no key needed)
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.k3s_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "k3s_node" {
  name = "${var.project}-${var.region_alias}-k3s-node-profile"
  role = aws_iam_role.k3s_node.name
}
