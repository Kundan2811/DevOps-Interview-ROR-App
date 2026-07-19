# Infrastructure — Ruby on Rails on AWS ECS Fargate

This directory contains the Terraform infrastructure and CI/CD pipeline used to deploy the Ruby on Rails application (in the repo root) to AWS.

## Architecture

```
GitHub Actions (CI/CD, OIDC auth)
      │ builds & pushes images
      ▼
Amazon ECR (rails-app, nginx repos)
      │ pulled by ECS on deploy
      ▼
┌─────────────────────────── VPC (10.0.0.0/16) ───────────────────────────┐
│                                                                          │
│  ┌─────────────── Public subnets (2 AZs) ───────────────┐               │
│  │              Application Load Balancer                │  ◄── Internet
│  │                    (port 80)                           │               │
│  └───────────────────────┬────────────────────────────────┘               │
│                           │                                                │
│  ┌─────────────── Private subnets (2 AZs) ──────────────────────────┐    │
│  │  ┌────────────────────┐        ┌─────────────────────┐          │    │
│  │  │  ECS Fargate task   │───────▶│   RDS Postgres        │          │    │
│  │  │  nginx + Rails      │  SQL   │   (encrypted)          │          │    │
│  │  │  (2 tasks, autoscale)│       └─────────────────────┘          │    │
│  │  └──────────┬──────────┘                                         │    │
│  └─────────────┼──────────────────────────────────────────────────────┘    │
│                │ IAM role (no static keys)                                │
│                ▼                                                          │
│     S3 bucket + Secrets Manager                                           │
└──────────────────────────────────────────────────────────────────────────┘
```

**Key design decisions:**
- **ECS Fargate over EKS** — no cluster nodes to patch/manage, faster to provision, matches the app's simple two-container shape.
- **Private subnets for everything except the ALB** — the ECS tasks and RDS instance have no public IPs and are unreachable from the internet directly, satisfying the assignment's "all resources private except the load balancer" requirement.
- **S3 access via IAM task role, not access keys** — the Rails container assumes an IAM role scoped to read/write only this app's specific bucket. No AWS credentials are embedded in the app or its environment.
- **RDS credentials via Secrets Manager** — injected into the container as ECS `secrets` at launch, not as plaintext environment variables in the task definition.
- **Two nginx configs** — Docker Compose (local dev) resolves sibling containers by name (`rails_app:3000`) via its embedded DNS. Fargate's `awsvpc` network mode has no such DNS; containers in the same task share one network interface and must talk via `localhost`. `docker/nginx/default.conf` + `Dockerfile` are for local Compose; `docker/nginx/default.ecs.conf` + `Dockerfile.ecs` are AWS-specific and use `localhost:3000`.
- **Remote Terraform state** — stored in S3 with DynamoDB locking (see `bootstrap/`), so state isn't just a local file at risk of loss.
- **CI/CD via GitHub Actions + OIDC** — no long-lived AWS access keys stored as GitHub secrets. GitHub's OIDC token is exchanged for short-lived AWS credentials, scoped to a role that can only push to this app's two ECR repos and deploy to this app's ECS service.

## Repository structure

```
infrastructure/
├── bootstrap/          # One-time setup: S3 bucket + DynamoDB table for Terraform state
│   └── main.tf
└── main/                # The actual application infrastructure
    ├── backend.tf        # Points at the bootstrap-created state bucket
    ├── provider.tf        # AWS + random providers
    ├── variables.tf        # All configurable values
    ├── vpc.tf                # VPC, subnets, NAT gateway, route tables
    ├── security_groups.tf     # ALB -> ECS -> RDS layered security groups
    ├── ecr.tf                   # Container image repositories
    ├── rds.tf                     # Postgres database
    ├── s3.tf                        # App storage bucket
    ├── secrets.tf                     # DB credentials in Secrets Manager
    ├── iam.tf                           # ECS task execution + task roles
    ├── alb.tf                             # Load balancer, target group, listener
    ├── ecs.tf                               # Cluster, task definition, service, autoscaling
    ├── github_action.tf                       # GitHub OIDC provider + CI/CD IAM role
    └── outputs.tf                               # ALB URL, ECR URLs, etc.

.github/
├── config.yaml           # Shared values used by both workflows
└── workflows/
    ├── ci.yaml             # Build validation on every push/PR (no AWS access)
    └── cd.yaml               # Build, push, deploy — runs on push to main only

docker/
├── app/
│   ├── Dockerfile
│   └── entrypoint.sh
└── nginx/
    ├── Dockerfile           # Local Docker Compose variant
    ├── default.conf           # Local Docker Compose variant
    ├── Dockerfile.ecs           # AWS/ECS variant
    └── default.ecs.conf           # AWS/ECS variant
```

## Prerequisites

- AWS account with an IAM user/role that has sufficient permissions (this project was built and tested with `AdministratorAccess`; a production setup would scope this down)
- AWS CLI v2, configured (`aws configure`)
- Terraform >= 1.5.0
- Docker Desktop

## Deployment steps (first-time setup)

### 1. Bootstrap the Terraform state backend

This creates the S3 bucket and DynamoDB table that the main infrastructure's state will live in. Only needs to be run once, ever.

```bash
cd infrastructure/bootstrap
terraform init
terraform plan
terraform apply
```

Note the `state_bucket_name` output — it's already wired into `infrastructure/main/backend.tf`.

### 2. Provision the main infrastructure

```bash
cd infrastructure/main
terraform init
terraform plan
terraform apply
```

This creates the VPC, ALB, ECS cluster/service, RDS instance, ECR repositories, IAM roles, S3 bucket, Secrets Manager secret, and the GitHub Actions OIDC trust relationship. RDS provisioning alone typically takes 5-9 minutes.

Note the `ecr_rails_app_repository_url`, `ecr_nginx_repository_url`, and `github_actions_role_arn` outputs — you'll need them for the next steps.

### 3. Configure GitHub Actions

1. Go to the repo's **Settings → Secrets and variables → Actions**
2. Add a repository secret named `AWS_GITHUB_ACTIONS_ROLE_ARN` with the value from the `github_actions_role_arn` Terraform output

### 4. Push to trigger the pipeline

```bash
git push origin main
```

This triggers `.github/workflows/cd.yaml`, which builds both images, tags them with the git commit SHA, pushes to ECR, and deploys a new ECS task definition revision. The workflow waits for the ECS deployment to stabilize before completing.

### 5. Verify

```bash
terraform output alb_dns_name
```

Open that URL in a browser — you should see the Rails application.

## How the CI/CD pipeline works

- **`ci.yaml`** runs on every push (except to `main`) and every pull request. It builds both Docker images to confirm they still compile cleanly. It needs no AWS credentials and is safe to run on PRs from forks.
- **`cd.yaml`** runs only on push to `main`. It:
  1. Authenticates to AWS via OIDC (no stored access keys)
  2. Builds and pushes both images to ECR, tagged `main-<short-sha>` (the ECR repos are configured with immutable tags, so `:latest` is deliberately not reused)
  3. Downloads the currently deployed ECS task definition
  4. Swaps in the two new image URIs, leaving every other setting (CPU, memory, roles, secrets) untouched
  5. Registers the new task definition revision and updates the ECS service
  6. Waits for the rolling deployment to reach a stable, healthy state

## Notable troubleshooting encountered during this deployment

- **AWS Free Tier RDS backup retention** — the default 7-day retention exceeded the free tier limit; reduced to 1 day.
- **RDS engine version** — Postgres 13.3 (matching the local `docker-compose.yml`) is no longer offered as an RDS-manageable version; 13.23 (the latest supported 13.x patch) is used instead.
- **ECS task OOM kill (exit code 137)** — the initial 0.5 vCPU / 1GB task definition was too small for Rails + nginx together; increased to 1 vCPU / 3GB.
- **nginx container exit code 1 on ECS** — `default.conf`'s `server rails_app:3000` upstream relies on Docker Compose's container-name DNS, which doesn't exist in Fargate's `awsvpc` mode. Resolved with the ECS-specific `default.ecs.conf` using `localhost:3000`.
- **GitHub Actions OIDC `AssumeRoleWithWebIdentity` denied** — GitHub's OIDC `sub` claim includes stable numeric org/repo IDs (e.g. `repo:owner@12345/repo@67890:ref:...`) rather than just plain names; the IAM trust policy condition was updated to match the actual claim format (confirmed via CloudTrail).

## Cost notes

Running resources (approximate, `us-east-1`): NAT Gateway (~$0.045/hr), ALB (~$0.0225/hr), RDS `db.t3.micro` (~$0.017/hr, free-tier eligible), 2x Fargate tasks (~$0.02/hr each). To pause spend without tearing down the whole stack:

```bash
aws ecs update-service --cluster devops-assignment-cluster --service devops-assignment-service --desired-count 0
aws rds stop-db-instance --db-instance-identifier devops-assignment-postgres
```

To fully tear down:
```bash
cd infrastructure/main && terraform destroy
cd ../bootstrap && terraform destroy
```
