
---

# AWS IAM OIDC Authentication Failure: GitHub Actions JWT Analysis & Resolution

## 🚨 Error Symptoms

Workflows fail at the authentication step with the error:

```text
Error: Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity

```

This occurs despite having a standard, syntactically correct AWS IAM OIDC trust policy configured.

---

## 🔍 Incident Investigation & Payload Analysis

### 1. Token Inspection Step

To inspect the JWT payload, the following diagnostic step was executed inside the GitHub Actions workflow prior to calling `aws-actions/configure-aws-credentials`:

```yaml
- name: Debug OIDC Token Claims
  run: |
    # Request ID token from GitHub OIDC provider
    TOKEN=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r '.value')
    
    # Decode base64 JWT payload
    echo "=== OIDC TOKEN PAYLOAD ==="
    echo "$TOKEN" | jq -R 'split(".") | .[1] | @base64d | fromjson'

```

### 2. Discrepancy Identified

The decoded JWT token revealed that GitHub formatted the `sub` claim with internal numerical IDs (`@277283673` and `@1323100445`):

```json
"sub": "repo:shaurya-security@277283673/flask-ecs-devops-pipeline@1323100445:ref:refs/heads/main"

```

However, the Terraform trust policy was configured with a strict string match using human-readable names:

```hcl
condition {
  test     = "StringEquals"
  variable = "token.actions.githubusercontent.com:sub"
  values   = ["repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main"]
}

```

Because AWS IAM evaluates trust conditions literally, strict string evaluation against `sub` failed completely.

---

## ⚠️ Key Constraint: AWS IAM Policy Validation

An initial attempt to fix this involved dropping the `sub` claim check entirely in favor of matching solely on `token.actions.githubusercontent.com:repository`.

However, AWS IAM rejects this with a `MalformedPolicyDocument` error:

```text
MalformedPolicyDocument: Trust policy with trusted principal [...] must evaluate, using StringEquals, StringLike or StringEqualsIgnoreCase, token.actions.githubusercontent.com:sub or token.actions.githubusercontent.com:job_workflow_ref which is not scoped to all.

```

**Takeaway:** AWS IAM strictly mandates evaluating either `sub` or `job_workflow_ref` to prevent open trust relationship vulnerabilities across tenant boundaries.

---

## 🛠️ The Final Working Solution

To satisfy **AWS IAM policy enforcement rules** while safely handling **GitHub's injected numerical IDs**, the trust policy was updated to use `StringLike` wildcards on `sub` alongside an exact `repository` check.

### Updated `github_oidc.tf`

```hcl
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

```

---

## 💡 Key Takeaways & Best Practices

1. **JWT Inspection:** Decoding OIDC tokens in CI/CD pipeline steps is the most effective way to debug claim-level condition failures.
2. **Wildcard Flexibility:** Accounts with GitHub Enterprise, custom policies, or unique org setups may inject account/repo IDs into the `sub` claim. Using `StringLike` with wildcards (`*`) accommodates structural differences without compromising security boundaries.
3. **Defense in Depth:** Combining wildcarded `sub` conditions with explicit `repository` checks keeps trust policies strict while adhering to AWS policy validator constraints.
