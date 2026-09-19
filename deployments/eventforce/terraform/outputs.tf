output "application_url" {
  value       = "https://${var.domain_name}"
  description = "Plane staging URL."
}

output "alb_dns_name" {
  value       = data.aws_lb.staging.dns_name
  description = "Create the public plane CNAME at this target."
}

output "backup_bucket" {
  value       = aws_s3_bucket.backups.id
  description = "Daily database and uploads backup bucket."
}

output "deploy_role_arn" {
  value       = aws_iam_role.github_deploy.arn
  description = "GitHub Actions OIDC deployment role."
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.plane.repository_url
  description = "ECR repository used for immutable per-service image tags."
}

output "instance_id" {
  value       = aws_instance.plane.id
  description = "SSM-managed Plane staging host."
}
