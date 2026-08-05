#############################################
# GitHub Actions OIDC Identity Provider
#############################################

resource "aws_iam_openid_connect_provider" "github" {

  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]
}

#############################################
# GitHub Actions Assume Role Policy
#############################################

data "aws_iam_policy_document" "github_oidc_assume_role" {

  statement {

    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {

      type = "Federated"

      identifiers = [
        aws_iam_openid_connect_provider.github.arn
      ]
    }

    condition {

      test = "StringEquals"

      variable = "token.actions.githubusercontent.com:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {

      test = "StringEquals"

      variable = "token.actions.githubusercontent.com:sub"

      values = [
        "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main"
      ]
    }
  }
}

#############################################
# GitHub Actions IAM Role
#############################################

resource "aws_iam_role" "github_actions" {

  name = "${local.owner}-github-actions-role"

  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume_role.json

  tags = {
    Name = "${local.owner}-github-actions-role"
  }
}

#############################################
# Permissions Required For CI/CD
#############################################

data "aws_iam_policy_document" "github_actions_policy" {

  statement {

    sid = "ECR"

    actions = [

      "ecr:GetAuthorizationToken",

      "ecr:BatchCheckLayerAvailability",

      "ecr:CompleteLayerUpload",

      "ecr:InitiateLayerUpload",

      "ecr:UploadLayerPart",

      "ecr:PutImage",

      "ecr:BatchGetImage"
    ]

    resources = [ aws_ecr_repository.app.arn ]
  }
}

resource "aws_iam_policy" "github_actions" {

  name = "${local.owner}-github-actions-policy"

  policy = data.aws_iam_policy_document.github_actions_policy.json
}

resource "aws_iam_role_policy_attachment" "github_actions" {

  role = aws_iam_role.github_actions.name

  policy_arn = aws_iam_policy.github_actions.arn
}

#############################################
# Output
#############################################

output "github_actions_role_arn" {

  value = aws_iam_role.github_actions.arn
}
