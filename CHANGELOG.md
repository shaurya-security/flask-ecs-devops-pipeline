# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] – Full Automation Release

**Theme:** Continuous Integration & Continuous Deployment with GitHub Actions

This release automates everything that was previously done by hand with
`push-to-ecr.sh`. A push to `main` now runs a full test/scan/build pipeline
and, on success, deploys automatically to Amazon ECS Fargate with zero
manual steps.

### Added
- GitHub Actions **Continuous Integration** workflow (`ci.yml`):
  - Python syntax check and Flask import verification.
  - `terraform fmt -check` and `terraform validate` (backend disabled for CI).
  - **Checkov** static security scanning of the Terraform codebase.
  - Docker image build, container smoke test, and `/health` + `/info`
    endpoint verification on every push and pull request.
- GitHub Actions **Continuous Deployment** workflow (`cd.yml`), triggered
  only after CI succeeds on `main`:
  - AWS authentication via **OIDC** — no long-lived AWS access keys.
  - Build, tag (by commit SHA), and push the image to Amazon ECR.
  - Download the current ECS task definition, render it with the new
    image, register a new revision, and roll it out to the ECS service.
  - `wait-for-service-stability` so the workflow only succeeds once the
    new tasks are healthy behind the ALB.
- **AWS IAM OIDC identity provider** (`github_oidc.tf`) and a dedicated,
  least-privilege IAM role that GitHub Actions assumes at runtime.
- Scoped IAM policies split across ECR authentication, ECR push, ECS
  task-definition management, ECS service deployment, and `iam:PassRole`
  for the ECS execution role — each granted only what that stage needs.
- `.checkov.yaml` with a documented list of intentionally accepted findings
  (e.g. HTTP-only ALB, public-subnet public IPs, AES256 over KMS) rather
  than a blanket suppression.
- Dynamic `APP_VERSION` build argument so a deployed container reports the
  exact commit SHA it was built from via `/info`.
- Project-visual assets (banner, architecture diagram, CI/CD diagram,
  and console/pipeline screenshots) under `assets/`.

### Changed
- Repository/project renamed from `flask-ecs-cicd-demo` to
  **`flask-ecs-devops-pipeline`** to better reflect its scope.
- Split the original single CI workflow into two dedicated workflows
  (`ci.yml` / `cd.yml`) so infrastructure/application validation and
  production deployment are decoupled and independently triggerable.
- ECS deployment permissions narrowed multiple times (from a broad `"*"`
  ECR policy down to per-action, per-resource statements) as the pipeline
  matured.

### Fixed
- **OIDC trust-policy mismatch:** GitHub's issued JWT `sub` claim included
  injected numeric IDs after the owner/repo names
  (`repo:owner@<id>/repo@<id>:ref:...`), which didn't match a strict
  `StringEquals` condition. Resolved by decoding the token in-workflow and
  switching to a `StringLike` wildcard on `sub` combined with an exact
  match on the `repository` claim.
- Terraform formatting failures caught and fixed by CI on several
  iterations (`terraform fmt -check -recursive`).
- Container/task-definition `container-name` mismatch between the render
  and deploy steps that broke the rolling deployment.
- Missing `ecr:ListImages` permission that caused image verification to
  fail after a successful push.
- Removed an early, unnecessary `terraform apply -auto-approve` step from
  CI — infrastructure changes are applied manually and deliberately;
  only the application image and ECS task definition are automated.
- Numerous Checkov findings triaged one at a time (10 initial findings:
  5 fixed — ECR tag immutability, CloudWatch retention, ALB deletion
  protection, dropped invalid headers, ALB access logging — 5 accepted
  as documented, in-scope trade-offs).

### Security
- Eliminated static AWS credentials from CI/CD entirely in favor of
  short-lived, OIDC-issued credentials scoped to this repository's
  `main` branch only.

---

## [1.0.1] – 2026-08-04

### Fixed
- ECS task definition wasn't passing environment variables through to the
  container, so `/health` and `/info` reported default placeholder values
  (`Flask Demo`, `0.0.1`) instead of the configured application name and
  version. Injected `APP_NAME`, `APP_VERSION`, and `DEBUG` directly into
  the ECS task definition so configuration comes from the environment,
  not the image — verified via `curl` against the ALB.

---

## [1.0.0] – 2026-08-04

**Theme:** Manual, verified deployment of a containerized Flask app to
AWS ECS Fargate

### Added
- Flask application with `/`, `/health`, and `/info` endpoints, configured
  via environment variables (`config.py`, `.env` / `.env.example`).
- Multi-stage `Dockerfile` producing a slim runtime image, served by
  **Gunicorn** with structured access/error logging to stdout/stderr.
- Terraform-provisioned AWS infrastructure:
  - Multi-AZ VPC with public/private subnets, Internet Gateway, and a
    managed NAT Gateway.
  - Amazon ECR repository (image scanning + AES256 encryption enabled).
  - IAM execution role for ECS tasks (AWS-managed
    `AmazonECSTaskExecutionRolePolicy`).
  - CloudWatch log group for container logs.
  - ECS Cluster, Task Definition (Fargate, 256 CPU / 512 MiB), and Service
    running tasks in private subnets only.
  - Application Load Balancer with an HTTP listener and a `/health`-based
    target group health check.
- `terraform_bootstrap/` for remote Terraform state (S3 backend with
  native state locking).
- `push-to-ecr.sh` — a portable helper script that reads the ECR
  repository URL from Terraform outputs, builds the image, authenticates
  Docker to ECR, tags, and pushes.
- End-to-end manual verification: `terraform apply` → `push-to-ecr.sh` →
  confirmed `/`, `/health`, and `/info` all responding correctly through
  the public ALB DNS name.
