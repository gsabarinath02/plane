variable "aws_region" {
  description = "AWS region containing the Eventforce staging VPC and ALB."
  type        = string
  default     = "ap-south-1"
}

variable "domain_name" {
  description = "Public hostname for Plane."
  type        = string
  default     = "plane.eventforce.in"
}

variable "attach_certificate" {
  description = "Attach the issued ACM certificate to the shared ALB. Set false only during initial DNS validation bootstrap."
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "EC2 instance type for the single-node staging deployment."
  type        = string
  default     = "t3.large"
}

variable "root_volume_size" {
  description = "Encrypted gp3 root volume size in GiB."
  type        = number
  default     = 100
}

variable "github_repository" {
  description = "GitHub repository trusted to deploy through OIDC."
  type        = string
  default     = "gsabarinath02/plane"
}

variable "github_branch" {
  description = "Git branch allowed to deploy to staging."
  type        = string
  default     = "eventforce-staging"
}

variable "github_oidc_subject_prefix" {
  description = "Immutable GitHub OIDC subject prefix, including owner and repository numeric IDs."
  type        = string
  default     = "repo:gsabarinath02@77834634/plane@1377593321"
}

variable "existing_vpc_name" {
  description = "Name tag of the existing Eventforce staging VPC."
  type        = string
  default     = "eventforce-staging-vpc"
}

variable "existing_public_subnet_name" {
  description = "Name tag of the public subnet used by the Plane host."
  type        = string
  default     = "eventforce-staging-public-1"
}

variable "existing_alb_name" {
  description = "Existing Eventforce staging ALB shared by the Plane host rule."
  type        = string
  default     = "eventforce-staging-alb"
}
