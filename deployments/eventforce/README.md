# Eventforce staging deployment

Plane staging runs at `https://plane.eventforce.in` in AWS account
`699258777121` (`ap-south-1`). The deployment deliberately uses a dedicated
EC2 host and dedicated Docker volumes so Plane cannot share or modify the
Eventforce application database, Redis cluster, or ECS services.

## Architecture

- Existing `eventforce-staging-alb` terminates TLS and routes the
  `plane.eventforce.in` host header to a dedicated target group.
- A keyless Amazon Linux 2023 EC2 instance accepts port 80 only from the ALB.
  Administration and deployments use AWS Systems Manager; SSH is not exposed.
- Six application images are built from this repository and stored as immutable
  service-and-commit tags in the `plane-staging` ECR repository.
- PostgreSQL, Valkey, RabbitMQ, and MinIO use persistent Docker volumes on an
  encrypted 100 GiB gp3 volume.
- A systemd timer uploads a daily PostgreSQL dump and MinIO archive to an
  encrypted, private S3 bucket with 35-day retention.
- GitHub Actions obtains short-lived AWS credentials through the existing
  GitHub OIDC provider. No long-lived AWS key is stored in GitHub.

## Delivery flow

Pull requests into `eventforce-staging` run application checks and validate the
Terraform and shell scripts. A push to `eventforce-staging` additionally builds
and pushes all images, then runs `/opt/plane/deploy.sh` through SSM. The script
runs database migrations, starts the new images, and restores the preceding
image tag when the local health check fails.

The deployed branch starts from upstream Plane `v1.4.2`. Keep the remotes as:

```text
origin   https://github.com/gsabarinath02/plane.git
upstream https://github.com/makeplane/plane.git
```

## Terraform

State is stored in the existing encrypted Eventforce Terraform bucket at
`plane/staging/terraform.tfstate` with native S3 locking.

For a local plan or apply, use the staging role profile only as a backend
override; do not commit a profile name into the provider configuration:

```bash
cd deployments/eventforce/terraform
terraform init -backend-config="profile=eventforce-staging-org"
AWS_PROFILE=eventforce-staging-org terraform plan
AWS_PROFILE=eventforce-staging-org terraform apply
```

The ACM certificate for `plane.eventforce.in` must be issued before Terraform
can resolve its data source. DNS is hosted at GoDaddy, so both the ACM
validation CNAME and the public `plane` CNAME are maintained there.

## Operations

```bash
# Find the managed host
aws ec2 describe-instances --region ap-south-1 \
  --filters Name=tag:Name,Values=plane-staging \
  --query 'Reservations[0].Instances[0].InstanceId' --output text

# Open a shell without exposing SSH
aws ssm start-session --region ap-south-1 --target INSTANCE_ID

# Inspect services on the host
sudo docker compose --env-file /opt/plane/runtime.env \
  --file /opt/plane/docker-compose.yml ps

# Run an on-demand backup
sudo /opt/plane/backup.sh
```

The generated runtime secrets exist only in `/opt/plane/runtime.env` with mode
`0600`; the file is never committed or printed by CI.
