data "aws_caller_identity" "current" {}

data "aws_vpc" "staging" {
  filter {
    name   = "tag:Name"
    values = [var.existing_vpc_name]
  }
}

data "aws_subnet" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.staging.id]
  }

  filter {
    name   = "tag:Name"
    values = [var.existing_public_subnet_name]
  }
}

data "aws_lb" "staging" {
  name = var.existing_alb_name
}

data "aws_lb_listener" "https" {
  load_balancer_arn = data.aws_lb.staging.arn
  port              = 443
}

data "aws_acm_certificate" "plane" {
  count = var.attach_certificate ? 1 : 0

  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  name = "plane-staging"
  tags = {
    Project     = "plane"
    Environment = "staging"
    ManagedBy   = "terraform"
    Repository  = var.github_repository
  }
}

resource "aws_ecr_repository" "plane" {
  name                 = local.name
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "plane" {
  repository = aws_ecr_repository.plane.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Retain the most recent 60 service images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["frontend-", "space-", "admin-", "live-", "backend-", "proxy-"]
          countType     = "imageCountMoreThan"
          countNumber   = 60
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Remove untagged layers after seven days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}

resource "aws_s3_bucket" "backups" {
  bucket = "plane-staging-backups-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "backup-retention"
    status = "Enabled"

    filter {}

    expiration {
      days = 35
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.backups]
}

resource "aws_security_group" "plane" {
  name        = local.name
  description = "Plane staging host; HTTP is accepted only from the shared ALB"
  vpc_id      = data.aws_vpc.staging.id

  ingress {
    description     = "HTTP from Eventforce staging ALB"
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    security_groups = [one(data.aws_lb.staging.security_groups)]
  }

  egress {
    description = "Outbound updates, image pulls, SSM, ECR, and S3"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = local.name }
}

resource "aws_instance" "plane" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.plane.id]
  iam_instance_profile        = aws_iam_instance_profile.plane.name

  monitoring              = true
  disable_api_termination = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = false
    iops                  = 3000
    throughput            = 125
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region     = var.aws_region
    backup_bucket  = aws_s3_bucket.backups.id
    domain_name    = var.domain_name
    ecr_repository = aws_ecr_repository.plane.repository_url
    deploy_script  = base64encode(file("${path.module}/../deploy.sh"))
    backup_script  = base64encode(file("${path.module}/../backup.sh"))
  })

  user_data_replace_on_change = false

  lifecycle {
    prevent_destroy = true
  }

  tags = { Name = local.name }

  depends_on = [
    aws_iam_role_policy.plane_runtime,
    aws_iam_role_policy_attachment.ssm_core,
  ]
}

resource "aws_lb_target_group" "plane" {
  name        = local.name
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.staging.id

  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 10
  }
}

resource "aws_lb_target_group_attachment" "plane" {
  target_group_arn = aws_lb_target_group.plane.arn
  target_id        = aws_instance.plane.id
  port             = 80
}

resource "aws_lb_listener_certificate" "plane" {
  count = var.attach_certificate ? 1 : 0

  listener_arn    = data.aws_lb_listener.https.arn
  certificate_arn = data.aws_acm_certificate.plane[0].arn
}

resource "aws_lb_listener_rule" "plane" {
  listener_arn = data.aws_lb_listener.https.arn
  priority     = 80

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.plane.arn
  }

  condition {
    host_header {
      values = [var.domain_name]
    }
  }
}
