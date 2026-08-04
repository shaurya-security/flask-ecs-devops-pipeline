#!/bin/bash

# Exit immediately if any command in the script fails
set -e

# ==========================================
# 🌟 PORTABLE ABSOLUTE PATH DETECTION
# ==========================================
# Identifies the directory where this script file actually lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"

# Target application configurations
IMAGE_TAG="3.0"
APP_NAME="flask-ecs-cicd-demo"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
APP_DIR="${PROJECT_ROOT}/app"

# ==========================================
# VALIDATION ENGINE
# ==========================================
echo "🔍 Syncing with Terraform environment..."

# Verify the main infrastructure workspace has been initialized
if [ ! -d "$TERRAFORM_DIR/.terraform" ]; then
    echo "❌ Error: Terraform workspace uninitialized. Run 'terraform init' in $TERRAFORM_DIR first."
    exit 1
fi

# Extract infrastructure context variables directly from Terraform outputs
FULL_ECR_URL=$(terraform -chdir="$TERRAFORM_DIR" output -raw ecr_repository_url)
AWS_REGION=$(terraform -chdir="$TERRAFORM_DIR" output -raw aws_region 2>/dev/null || echo "ap-south-1")

# Format registry parameters
ECR_REGISTRY=$(echo "$FULL_ECR_URL" | cut -d'/' -f1)
FULL_IMAGE_NAME="${FULL_ECR_URL}:${IMAGE_TAG}"

echo "📍 Registry Target: ${ECR_REGISTRY}"
echo "📦 Image Target:    ${FULL_IMAGE_NAME}"
echo "--------------------------------------------"

# ==========================================
# EXECUTION LIFECYCLE
# ==========================================

# Step 1: Build the Docker Image using its absolute path location
echo "🔨 Step 1: Compiling local Docker image from $APP_DIR..."
docker build -t "${APP_NAME}:${IMAGE_TAG}" "$APP_DIR"

# Step 2: Authenticate with AWS ECR
echo "🔐 Step 2: Authenticating Docker CLI session with AWS ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# Step 3: Tag the Image for the remote registry context
echo "🏷️ Step 3: Applying cloud deployment labels..."
docker tag "${APP_NAME}:${IMAGE_TAG}" "${FULL_IMAGE_NAME}"

# Step 4: Push to AWS Cloud
echo "🚀 Step 4: Shipping container image layers to ECR..."
docker push "${FULL_IMAGE_NAME}"

echo "--------------------------------------------"
echo "🎉 Deployment Complete! Container image version ${IMAGE_TAG} is live in your ECR Registry."
