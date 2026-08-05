# Error Symtoms 
Persisting Error of "Error: Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity"
Despite theoretically robust AWS OIDC configuration. 

# Effective Problem Recon

In CI workflow: 

      - name: Debug OIDC Token Claims
        run: |
          # Request ID token from GitHub OIDC provider
          TOKEN=$(curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r '.value')
          
          # Decode base64 payload to inspect claims
          echo "=== OIDC TOKEN PAYLOAD ==="
          echo "$TOKEN" | jq -R 'split(".") | .[1] | @base64d | fromjson'

      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ap-south-1

# Findings 
Result from Github Actions : 

  "sub": "repo:shaurya-security@277283673/flask-ecs-cicd-demo@1323100445:ref:refs/heads/main",

While my config : 
    condition {

      test = "StringEquals"

      variable = "token.actions.githubusercontent.com:sub"

      values = [
        "repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main"
      ]
    }


# Precise problem and fix

```json
"sub": "repo:shaurya-security@277283673/flask-ecs-cicd-demo@1323100445:ref:refs/heads/main"

```

Those **`@277283673`** and **`@1323100445`** string injections inside my `sub` claim.

### Why is this happening?

My GitHub account/repo is customized or managed under an enterprise policy that formats `sub` using **Repository IDs** (e.g., `repo:<owner-id>/<repo-id>:ref:...`) rather than standard names (`repo:<owner>/<repo>:ref:...`).

Because AWS IAM evaluates My conditions strictly against the string you pass, matching `repo:shaurya-security/flask-ecs-cicd-demo:*` fails completely!

---

## The Fix

Instead of matching against `sub` (which contains injected numerical IDs in my setup), match against the **`repository`** claim directly! Line `52` of my payload shows:

```json
"repository": "shaurya-security/flask-ecs-cicd-demo"

```

### Update `github_oidc.tf`

Update my trust policy condition in Terraform to use `repository` instead of `sub`:

```hcl
data "aws_iam_policy_document" "github_oidc_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # Audience check
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Match exact repository full path (avoids sub formatting/ID issues entirely)
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository"
      values   = ["${var.github_owner}/${var.github_repo}"]
    }
  }
}

```

---

### Alternative: Wildcarding `sub`

If you still want to condition on `sub`, you can use `StringLike` with wildcards to bypass the injected IDs:

```hcl
condition {
  test     = "StringLike"
  variable = "token.actions.githubusercontent.com:sub"
  values   = ["repo:${var.github_owner}*/*:ref:refs/heads/main"]
}

```

> **Recommendation:** Using **`token.actions.githubusercontent.com:repository`** (the first snippet) is cleaner, safer, and completely immune to how GitHub formats `sub` across different account configurations.

Run `terraform apply` and re-run my action!
