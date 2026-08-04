
<p align="center">
 <img src="assets/banner_ecs_fargate.png" alt="Containerized Flask Deployment on AWS ECS Fargate" width="100%">
</p>

<h1 align="center">

Containerized Flask Deployment on AWS ECS Fargate

</h1>

<p align="center">

A production-style AWS container deployment project demonstrating
Infrastructure as Code with Terraform, multi-stage Docker builds, Amazon
ECS Fargate, Amazon ECR, Application Load Balancer, CloudWatch logging,
and production-oriented container deployment practices.

<p align="center">

<img src="https://img.shields.io/badge/Terraform-IaC-7B42BC?logo=terraform">
<img src="https://img.shields.io/badge/Docker-Containerized-2496ED?logo=docker">
<img src="https://img.shields.io/badge/AWS-ECS_Fargate-FF9900?logo=amazonaws">
<img src="https://img.shields.io/badge/AWS-ECR-FF9900">
<img src="https://img.shields.io/badge/Application_Load_Balancer-HTTP-FF9900">
<img src="https://img.shields.io/badge/CloudWatch-Logging-FF4F8B">
<img src="https://img.shields.io/badge/Gunicorn-Production_Server-499848">

</p>


------------------------------------------------------------------------

# Overview

This project demonstrates the complete deployment lifecycle of a
containerized web application on AWS.

A lightweight Flask application is packaged into a multi-stage Docker
image, published to Amazon Elastic Container Registry (ECR), and
deployed onto Amazon ECS Fargate behind an Application Load Balancer.
The supporting cloud infrastructure---including networking, IAM,
logging, and container orchestration---is provisioned entirely with
Terraform.

Unlike traditional EC2-based deployments, the application runs as an
immutable container workload. Infrastructure and application deployment
are separated, allowing the same container image to be deployed
repeatedly without modifying the underlying environment.

This repository represents the latest stage in an evolving cloud infrastructure journey:

- **v0:** AWS CLI Infrastructure → End-to-end infrastructure provisioned using the AWS CLI, including a VPC, EC2 instances, Bastion-as-NAT, SSH administration, and a CloudTrail + VPC Flow Logs pipeline feeding Wazuh.
- 
- **v1:** Terraform Foundation → Rebuilt the infrastructure using Terraform while retaining the Bastion-as-NAT architecture and SSH-based administration.
- 
- **v2:** Secure Terraform Networking → Replaced the NAT instance with a managed NAT Gateway, adopted AWS Systems Manager (SSM) for administration, introduced remote Terraform state, GitHub Actions CI, and Checkov security scanning.
- 
- **v3 (current):** Containerized Application Platform → Shifted from provisioning virtual machines to deploying immutable containerized applications on Amazon ECS Fargate using Docker, Amazon ECR, Application Load Balancer, CloudWatch Logs, and Terraform.

The objective is not to build a feature-rich Flask application, but to
demonstrate modern cloud deployment practices used for containerized
workloads.

------------------------------------------------------------------------

# Key Capabilities

-   ✅ Multi-stage Docker image builds
-   ✅ Production-ready Gunicorn application server
-   ✅ Amazon ECS Fargate deployment
-   ✅ Amazon ECR container registry
-   ✅ Application Load Balancer with health checks
-   ✅ Private ECS Tasks
-   ✅ CloudWatch centralized logging
-   ✅ Infrastructure as Code with Terraform
-   ✅ Remote Terraform state
-   ✅ Automated container publishing helper

------------------------------------------------------------------------

# Architecture

## Infrastructure

-   **Region:** ap-south-1
-   **Container Runtime:** Amazon ECS Fargate
-   **Container Registry:** Amazon ECR
-   **Application:** Flask + Gunicorn

### Networking

-   VPC
-   Multi-AZ Public Subnets
-   Multi-AZ Private Subnets
-   Internet Gateway
-   NAT Gateway
-   Public Application Load Balancer

### Container Platform

-   Amazon ECS Cluster
-   ECS Task Definition
-   ECS Service
-   Amazon ECR Repository

### Security

-   IAM Execution Role
-   Dedicated Security Groups
-   Private ECS Tasks
-   ALB-to-Task communication only

### Observability

-   Amazon CloudWatch Log Group
-   Container access logs
-   Application health endpoint

> Add an architecture diagram here
> (`assets/ecs_fargate_architecture.png`).

------------------------------------------------------------------------

# Repository Structure

``` text
.
├── app/
│   ├── app.py
│   ├── config.py
│   ├── Dockerfile
│   ├── requirements.txt
│   └── templates/
│
├── terraform/
│   ├── alb.tf
│   ├── cloudwatch.tf
│   ├── data.tf
│   ├── ecr.tf
│   ├── ecs.tf
│   ├── iam.tf
│   ├── network.tf
│   ├── locals.tf
│   ├── variables.tf
│   ├── provider.tf
│   ├── backend.tf
│   └── versions.tf
│
├── terraform_bootstrap/
│   ├── backend.tf
│   ├── provider.tf
│   └── s3.tf
│
└── push-to-ecr.sh
```

------------------------------------------------------------------------

# Deployment Workflow

``` text
Developer

    │

Docker Build

    │

Docker Image

    │

Amazon ECR

    │

Amazon ECS Fargate

    │

Application Load Balancer

    │

Browser
```

Application traffic follows the runtime path below:

``` text
Browser
    │
Application Load Balancer
    │
Target Group (/health)
    │
ECS Service
    │
Fargate Task
    │
Gunicorn
    │
Flask Application
```

------------------------------------------------------------------------

# Deployment

## Prerequisites

-   Terraform \>= 1.10
-   AWS CLI v2
-   Docker
-   AWS account

## 1. Bootstrap Remote State

``` bash
cd terraform_bootstrap
terraform init
terraform apply
```

## 2. Deploy Infrastructure

``` bash
cd terraform
terraform init
terraform apply
```

## 3. Build & Publish the Container

``` bash
./push-to-ecr.sh
```

## 4. Access the Application

``` text
http://<application-load-balancer-dns>
```

------------------------------------------------------------------------

# Application Endpoints

  Endpoint    Purpose
  ----------- ----------------------
  `/`         Application homepage
  `/health`   ALB health checks
  `/info`     Application metadata

------------------------------------------------------------------------

# Future Improvements

-   [ ] GitHub Actions CI/CD pipeline
-   [ ] Automatic ECS rolling deployments
-   [ ] HTTPS with ACM
-   [ ] Route53 custom domain
-   [ ] ECS Auto Scaling
-   [ ] AWS Secrets Manager
-   [ ] AWS WAF
-   [ ] Blue/Green deployments

------------------------------------------------------------------------

# Related Projects

  -----------------------------------------------------------------------
  Repository                         Description
  ---------------------------------- ------------------------------------
  **aws-infra-cli**                  AWS infrastructure provisioned using
                                     the AWS CLI

  **terraform-aws-secure-vpc**       Secure AWS networking with Terraform

  **aws-cloud-detection-pipeline**   Cloud detection engineering using
                                     AWS telemetry
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# License

This project is licensed under the **MIT License**.
