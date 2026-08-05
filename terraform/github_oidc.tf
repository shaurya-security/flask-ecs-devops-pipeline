#############################################
# GitHub Actions OIDC Identity Provider
#############################################

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS manages GitHub OIDC root CAs automatically; empty list avoids root cert rotation breakages
  thumbprint_list = []
}

#############################################
# GitHub Actions Assume Role Policy
#############################################

data "aws_iam_policy_document" "github_oidc_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # 1. Enforce correct token audience
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # 2. Satisfy AWS IAM mandatory 'sub' check using wildcards for ID strings
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}*/*:ref:refs/heads/main"]
    }

    # 3. Enforce precise repository path matching
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository"
      values   = ["${var.github_owner}/${var.github_repo}"]
    }
  }
}

#############################################
# GitHub Actions IAM Role
#############################################

resource "aws_iam_role" "github_actions" {
  name               = "${local.owner}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume_role.json

  tags = {
    Name = "${local.owner}-github-actions-role"
  }
}

#############################################
# Permissions Required For CI/CD
#############################################

data "aws_iam_policy_document" "github_actions_policy" {
  # Statement 1: ECR Authentication & Registry Read (Requires "*" resources)
  statement {
    sid = "ECRAuthAndRead"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:DescribeRepositories"
    ]

    resources = ["*"]
  }

  # Statement 2: Scoped Image Push/Pull Permissions for specific repository
  statement {
    sid = "ECRRepositoryAccess"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:ListImages"
    ]

    resources = [aws_ecr_repository.app.arn]
  }

# Statement 3a: Read/Register Task Definitions (Requires "*" as task definitions are version-appended)
  statement {
    sid = "ECSTaskDefManagement"

    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition"
    ]

    resources = ["*"]
  }

  # Statement 3b: Scoped ECS Service Deployment Actions
  statement {
    sid = "ECSServiceDeployment"

    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices"
    ]

    resources = [
      aws_ecs_service.flask.id
    ]
  }
  # Statement 4: IAM PassRole Permission for ECS Task Execution Role
  statement {
    sid = "PassExecutionRole"

    actions = [
      "iam:PassRole"
    ]

    resources = [
      aws_iam_role.ecs_execution_role.arn
    ]
  }
}

resource "aws_iam_policy" "github_actions" {
  name   = "${local.owner}-github-actions-policy"
  policy = data.aws_iam_policy_document.github_actions_policy.json
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}

#############################################
# Output
#############################################

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
