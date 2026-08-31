# Secure ECS Platform — Build Notes

Personal notes from building the Flask → Docker → ECR → ECS Fargate → ALB → CloudWatch pipeline (repo eventually renamed `flask-ecs-devops-pipeline`). Covers the reasoning behind each decision and the real problems hit along the way, in the order they came up.

---

## 1. Why this project, and why this scope

Started from a "bridge the gap" prompt aimed at going from "Cloud Operator" to "DevOps Associate" — the original suggestion included EKS/Kubernetes as an option, but that was deliberately dropped for this project. Kubernetes is a rabbit hole (architecture, kubectl, manifests, services, ingress, networking, autoscaling, RBAC, Helm...) and for an entry-level portfolio, **one polished ECS project beats a half-understood Kubernetes project.** (EKS became its own separate, later project.)

Final target architecture, decided up front and mostly followed exactly:
```
GitHub → GitHub Actions (test, build, push, deploy) → Amazon ECR
   → ECS Fargate → Application Load Balancer → Flask app → CloudWatch
```
Terraform stays at the center — infrastructure is never clicked together in the console.

**Rule for scope discipline:** stop adding AWS services once the core pipeline works; spend the remaining time on README/diagrams/screenshots instead of bolting on HTTPS/WAF/autoscaling/blue-green. Those got explicitly parked as "future improvements," not half-implemented.

**Rule for how much Flask to actually learn:** roughly 10% Flask / 90% DevOps. Flask is a vehicle, not the subject — enough to write routes, return JSON, and use templates; skip blueprints, context processors, Jinja macros, sessions/auth entirely. The `/health` endpoint is the one piece of "arbitrary-seeming" app code that's worth understanding deeply on day one, because it ends up wired into Docker, the ALB target group health check, and (later) ECS/Kubernetes probes.

---

## 2. Application-layer decisions

- Two routes to start: `/` (HTML) and `/health` (JSON `{"status": "healthy"}`). `/info` (app name, version, server) added later specifically so that hitting a URL after a deploy tells you which version/task actually answered — useful once multiple revisions exist.
- Configuration externalized early via `python-dotenv` + a `Config` class reading `os.getenv(...)` with defaults — before Docker existed. Reasoning: config should come from the environment, not hardcoded values, so the exact same code runs locally (`.env`, `DEBUG=True`) and in ECS (task-definition env vars, `DEBUG=False`) with zero code changes. `.env` is gitignored; `.env.example` is committed as documentation.
- Local dev server (`app.run()`) replaced with **Gunicorn** once Flask itself warned it isn't for production. Decision to use Gunicorn's `app:app` module:variable convention rather than anything custom.
- Multi-stage Dockerfile adopted specifically as a *pattern to learn*, not because this Flask app benefits much size-wise (savings were only a few MB). The value: builder stage does `pip install --prefix=/install`, runtime stage does `COPY --from=builder /install /usr/local` plus explicit `COPY app.py / config.py / templates` — no README/Dockerfile/.env.example baked into the image. Framed as the same shape used for Go binaries, React static builds, or Java JARs, where the win is much bigger.
- Logging: kept Gunicorn's access logs enabled (not disabled) even though the default log line was noisy, because these become the CloudWatch logs later — throwing them away throws away observability. Compromise: customized `--access-logformat` to a compact `%(m)s %(U)s %(s)s %(D)sµs` instead of turning logs off.
- `EXPOSE` clarified as documentation only — it does not publish a port; `docker run -p` does.

---

## 3. Terraform / infra decisions

- `locals.tf` centralizes all naming (`owner`, `vpc_name`, subnet/route-table/security-group name patterns, ECS cluster/service names) so the whole stack can be renamed via one `owner` variable, and `default_tags` on the AWS provider means resources don't repeat tags individually.
- **Two distinct IAM roles for ECS, kept separate on purpose**: an **Execution Role** (AWS-side — "can I start this container," pull from ECR, write to CloudWatch, via the AWS-managed `AmazonECSTaskExecutionRolePolicy`) versus a **Task Role** (app-side — what the running Flask code itself is allowed to call via boto3, left empty since the app didn't need AWS access yet). Called out explicitly as a common beginner mistake — collapsing both into one overly-permissive role.
- **Resource build order was deliberate, not default-tutorial order**: IAM → ECS Cluster → CloudWatch Log Group → Task Definition → ALB (LB, Target Group, Listener) → ECS Service *last*, because the Service depends on almost everything else. Explicitly avoided creating the `aws_ecs_service` early the way many tutorials do.
- CloudWatch Log Group created *before* the ECS task definition, since the task definition references it. Retention set to 7 days for a learning project (cost-conscious), noted that production usually runs 30–90 days.
- Target Group uses `target_type = "ip"` (not instance ID) because Fargate tasks are ENI-backed, not EC2-backed — this is a real Fargate-vs-EC2-launch-type distinction worth being able to explain.
- ALB health check path is `/health`, tying the earlier "trivial" Flask endpoint directly to real infrastructure behavior (200 = traffic flows, else ALB stops routing to that target).
- ECS Service: `assign_public_ip = false` and tasks placed in private subnets — the only public-facing thing is the ALB; the architecture is Internet → public ALB → private Fargate tasks → NAT Gateway for any outbound. `depends_on = [aws_lb_listener.http]` added explicitly because Terraform's automatic dependency inference wasn't trusted to sequence "listener must exist before service" correctly on its own.
- **Container name must match exactly** between the task definition's container name and the service's `load_balancer.container_name` — noted as a real gotcha (`flask` vs `flask-ecs-cicd-demo` mismatch silently breaks target group attachment).
- HTTPS deliberately postponed. ALB only has an HTTP:80 listener; ACM + Route53 + DNS validation was scoped out as "its own lesson," not mixed into the core ECS deployment.
- ECR: image tag mutability started as `MUTABLE`, later hardened to `IMMUTABLE` (a real fix, not skipped) in response to a Checkov finding — reasoning: immutable tags are genuinely good practice and cheap to adopt, unlike some other findings that would have meant scope creep.
- Image tagging strategy: kept **both** a semantic/manual tag scheme (`1.0`, `2.0`, `3.0`) for hand-built images and, once CI existed, the Git commit SHA (`${{ github.sha }}`) for pipeline-built images — production systems commonly push multiple tags at the same digest (e.g. `3.1`, `latest`, `<sha>` all pointing at one image). Tags are just labels; the digest is the immutable identity, and production ECS deployments generally pin on that identity.
- `push-to-ecr.sh` deliberately reads its target (`ecr_repository_url`, region) from **Terraform outputs** rather than hardcoding account ID/registry — "Terraform is the source of truth" carried through into the deploy tooling, not just the infra.

---

## 4. Real problems hit, and the actual fixes

### 4.1 Gunicorn "went silent" — logging format, not a logging failure
Switching from Flask's dev server to Gunicorn made request logs seem to disappear. Root cause: Gunicorn doesn't log every HTTP request by default the way Flask's dev server does — only startup info and errors. Fix: explicitly enable `--access-logfile -` and `--error-logfile -` (the `-` means stdout/stderr, not a file) so logs flow `Gunicorn → stdout → Docker logs → (later) CloudWatch Logs`. Then iterated on the **format** because the default access-log line was "ugly" — landed on a compact custom `--access-logformat` instead of disabling logs entirely, specifically because these logs become CloudWatch evidence later and disabling them would throw away debugging capability for something as simple as cosmetics.

### 4.2 Browser "can't load the ALB" — not an AWS bug
Brave browser failed to load the HTTP-only ALB URL while Firefox worked fine. Diagnosis: Brave's HTTPS-first ("always use secure connections") setting silently rewrote `http://` to `https://`, and the ALB genuinely had no HTTPS listener/ACM cert at that stage — so the browser's own upgrade attempt failed, not AWS. Confirmed via DevTools Network tab showing the auto-upgraded request. Lesson: verify with `curl` (protocol-explicit) before assuming an AWS misconfiguration; distinguish a client-side security feature from a real deployment issue.

### 4.3 App running, but showing default values instead of configured ones
After a successful ECS deployment, `/info` and `/health` returned `"application": "Flask Demo", "version": "0.0.1"` — the Python defaults — instead of the real configured values. Root cause: the container never received the environment variables at all; ECS doesn't automatically inject a local `.env` file, and copying `.env` into the image is an anti-pattern that was avoided on purpose. Fix: added an explicit `environment = [...]` block to the ECS task definition (`APP_NAME`, `APP_VERSION`, `DEBUG`) so Terraform → Task Definition → container env vars, matching the Twelve-Factor pattern already used locally. `python-dotenv`'s `load_dotenv()` was left in the code unchanged — it just silently no-ops when `.env` doesn't exist, so no code change was needed, only the infra side.
- This bug was caught **after** an initial `v1.0.0` tag had already been cut. Decision: don't rewrite git history over a small config bug — ship the fix as `v1.0.1` (a proper patch release under semver) rather than force-pushing a corrected `v1.0.0`.

### 4.4 GitHub OIDC trust policy: the `sub` claim mismatch (the big one — originated on this project)
- **Symptom:** every OIDC-based workflow run failed at the AWS credentials step with `Not authorized to perform sts:AssumeRoleWithWebIdentity`, despite what looked like a completely standard, correctly-written trust policy (`StringEquals` on `sub` matching `repo:owner/repo:ref:refs/heads/main`).
- **Investigation:** added a temporary workflow step to pull the raw OIDC token from GitHub's token endpoint and decode the JWT payload with `jq`. This revealed GitHub was actually issuing a `sub` claim with **internal numeric IDs baked in** — `repo:shaurya-security@277283673/flask-ecs-cicd-demo@1323100445:ref:refs/heads/main` — not the clean human-readable string the trust policy expected. A strict `StringEquals` check could never match that.
- **First fix attempt (rejected by AWS):** drop the `sub` condition entirely and rely only on matching `token.actions.githubusercontent.com:repository`. AWS IAM refused this outright with `MalformedPolicyDocument`, because **AWS mandates that a GitHub OIDC trust policy evaluate either `sub` or `job_workflow_ref`** — a deliberate guardrail against overly-open federated trust relationships.
- **Final fix:** keep `sub`, but switch to `StringLike` with a wildcard pattern (`repo:${owner}*/*:ref:refs/heads/main`) so the numeric-ID variant matches, **and** add back an exact `StringEquals` check on the `repository` claim as a second, precise condition. Defense in depth: one loose-but-mandatory condition plus one strict condition.
- Documented the whole investigation as an incident writeup (`docs/incidents/oidc-sub-claim-mismatch.md`) rather than just quietly patching it — treated as a genuine debugging artifact worth keeping, including the JWT-decoding technique itself (kept in notes, deliberately *not* left in the production workflow permanently once it had served its purpose).
- This exact incident and fix were later reused almost verbatim when standing up OIDC for the follow-on EKS project — only the downstream permissions (ECR-only vs. ECR + `eks:DescribeCluster` + access entries) differed.

### 4.5 `ecr:GetAuthorizationToken` needs `resources = ["*"]`
Separate, smaller IAM lesson surfaced while reviewing the OIDC policy: `ecr:GetAuthorizationToken` doesn't support resource-level scoping the way `ecr:PutImage`/`ecr:BatchGetImage` etc. do against a specific repo ARN — it has to be `"*"`. Not the cause of the OIDC failure (that was purely a trust-policy issue), but a real IAM permissions detail worth remembering when writing least-privilege ECR policies.

### 4.6 Checkov: CKV vs CKV2 rule-ID typo
Spent time re-running the pipeline confused about "still getting the same 3 Checkov errors after adding a skip," before realizing the skip list had the plain `CKV_AWS_11` ID while the actual failing check was `CKV2_AWS_11` — a completely different rule under a different Checkov engine (graph-based checks vs. resource-based checks), not a typo of the same rule. Lesson kept verbatim in notes: "different rule, different engine, different ID" — always copy the exact ID from the failure output rather than assuming.

### 4.7 Checkov findings triage — deciding what to fix vs. accept
Ran through two rounds of Checkov findings and explicitly classified each one as **fix now**, **accept as a documented trade-off**, or **defer as a future feature**, rather than either ignoring Checkov or chasing 100% compliance:
- **Fixed:** ECR tag immutability, CloudWatch log retention (bumped to 365 days), ALB deletion protection, `drop_invalid_header_fields`, hardened the VPC's **default security group** to allow nothing (Terraform doesn't harden this automatically — has to be done explicitly), added ALB access logging.
- **Accepted and documented in `.checkov.yaml` + README** (not silently suppressed): HTTP-only ALB listener (ACM/HTTPS is a planned future version), public subnets assigning public IPs (required — that's where the ALB lives), AES256 instead of customer-managed KMS (kept the project focused), no HTTP→HTTPS redirect (can't redirect to a protocol that doesn't exist yet), no WAF (out of scope), unrestricted egress from ECS tasks/ALB (needed, and restricting it added complexity without proportional benefit for this project).
- Principle: the README should show *engineering judgment*, not a perfect scanner score — explicitly reasoned trade-offs are a stronger signal than blind 100% compliance.

### 4.8 ECS deploy action: wrong identifier for `--task-definition`
`aws ecs describe-task-definition --task-definition shaurya-devops-flask-service` failed with `ClientException: Unable to describe task definition` — because that string was the **service** name, not the **task definition family**. ECS has three distinct object types (`Cluster → Service → Task Definition family → Revision`) and they don't share identifiers. Fixed by first querying the *service* for its current task definition ARN (`aws ecs describe-services ... --query "services[0].taskDefinition"`), then describing *that* ARN/family to confirm the container name. Reinforced the rule that **cluster name, service name, and container name must all be known exactly** before wiring the `amazon-ecs-render-task-definition` / `amazon-ecs-deploy-task-definition` GitHub Actions.

### 4.9 CI/CD IAM permissions grew iteratively through real failures, not upfront design
The GitHub Actions IAM role's permission set was built by hitting missing-permission errors one at a time and adding exactly the needed action, rather than guessing a full policy up front: added ECR push/pull actions, then discovered `ecr:ListImages`/`ecr:DescribeRepositories` were needed for the verification steps and added them, then added `ecs:DescribeTaskDefinition` / `ecs:RegisterTaskDefinition` / `ecs:UpdateService` / `ecs:DescribeServices` plus `iam:PassRole` scoped to the ECS execution role's ARN specifically for the deploy step (registering a task definition requires being allowed to pass the execution role to ECS). Treated as a normal, expected way to arrive at a least-privilege policy rather than a sign of poor planning.

### 4.10 Intentionally breaking CI to prove it actually catches regressions
After the CI pipeline was green, deliberately introduced real breakages one at a time and pushed them, to verify the pipeline would actually fail rather than just always passing:
- Renamed `/health` to `/healthy` in the app but didn't update anything else → CI correctly failed at the health-check curl step.
- Edited the Dockerfile's `WORKDIR` from `/app` to `/temp`, expecting a break.
- **Interesting result:** this one *passed* even though it "looked" broken. Reason: the subsequent `COPY` instructions still copied into the (now-renamed) working directory consistently, and Gunicorn starts relative to the container's current working directory regardless of what it's called — so nothing was actually functionally broken, just relocated. Real lesson recorded: not every suspicious-looking diff is a functional regression; the CI was right to pass it, and correctly distinguishing "looks wrong" from "is wrong" is itself a useful skill.
- This exercise is why the CI can be trusted as a real regression gate rather than pipeline theater.

### 4.11 Deciding *not* to run `terraform apply` inside the CI/CD pipeline
Early iteration briefly included a `Terraform Apply on Merge` step (`terraform apply -auto-approve` on push to `main`), which was later removed. Reasoning that stuck: infrastructure changes (`ecs.tf`, `vpc.tf`, etc.) are infrequent and deserve a human review/approval step, while application changes (editing `app.py`) happen many times a day and shouldn't trigger a 5–10 minute infra apply that touches nothing infrastructural. Landed on two separate lifecycles: Terraform stays a manual/human-triggered pipeline (`fmt` → `validate` → `checkov`, apply run by hand), while the CI/CD pipeline only ever pushes new application images and updates the ECS service — it never runs `terraform apply`. This is also why Terraform provisions the *shape* of things (cluster, service, task-definition template, IAM, ALB, networking) while GitHub Actions does the actual per-commit deployment by talking to the ECS API directly (describe → render new image → register revision → update service → wait for stability), rather than having Terraform manage the running container image at all.

### 4.12 CD triggering on failed CI runs
Once CI/CD were split into separate `ci.yml` / `cd.yml` workflows (`cd.yml` triggered via `workflow_run` on completion of `ci.yml`), noted that `workflow_run: types: [completed]` fires on **failed** CI runs too, not just successful ones — without an explicit `if: github.event.workflow_run.conclusion == 'success'` guard, a broken commit could still trigger a deployment attempt. Added the conditional as a required fix, not a nice-to-have.

### 4.13 Redundant Docker builds and unpinned deployment target names
Cleanup pass on the completed workflow: the pipeline was building the Docker image twice (once for the local health-check test, again right before pushing to ECR) — consolidated into a single build → test → tag → push sequence. Also replaced hardcoded `cluster:`/`service:`/repository-name strings scattered across multiple steps with a single `env:` block (`AWS_REGION`, `ECR_REPOSITORY`, `ECS_CLUSTER`, `ECS_SERVICE`, `TASK_DEFINITION`) referenced everywhere via `${{ env.* }}`, and added `concurrency: { group: ecs-production, cancel-in-progress: true }` so that pushing several commits in quick succession only ever deploys the latest one instead of racing multiple deployments against each other.

---

## 5. CI/CD pipeline evolution (shape, not just steps)

Ended up split into two workflows with a clean separation of concerns:

- **`ci.yml`** — runs on every push/PR to `main`; never touches AWS deployment. Steps: checkout → Python setup → install deps → `python -m compileall` + `python -c "import app"` (syntax/import check) → `terraform fmt -check` → `terraform init -backend=false` → `terraform validate` → Checkov scan → Docker build → run container → curl `/health` and `/info` → cleanup (`if: always()` so cleanup runs even on failure).
- **`cd.yml`** — triggered by a successful `ci.yml` run on `main` (`workflow_run`, gated on `conclusion == 'success'`). Steps: OIDC auth → ECR login → build/tag/push image (tagged with `${{ github.sha }}`, not a mutable version string) → download current task definition → render new task definition with the new image via `amazon-ecs-render-task-definition` → deploy via `amazon-ecs-deploy-task-definition` with `wait-for-service-stability: true`.

Deliberate ordering principle used throughout: build the *cheapest, fastest-failing* checks first (Python syntax) before the *expensive* ones (Docker build, container health test), and never let the pipeline touch AWS credentials until everything before it has already passed.

Debugging order established for runtime issues (used repeatedly): **ALB → Target Group → ECS Service → Task → CloudWatch Logs.** Going top-down through that chain generally isolates the failure in a few minutes instead of guessing.

---

## 6. Release / git hygiene decisions

- Adopted semantic versioning per-repo from the first meaningful milestone: `v1.0.0` = first working ECS Fargate deployment (Flask, Docker, Gunicorn, multi-stage build, ECR, Terraform, VPC, ALB, IAM, CloudWatch all working together) — everything after that is an enhancement, not a prerequisite (`v1.0.1` = env-var bug patch, `v1.1.0` planned as GitHub Actions CI/CD, etc.).
- Explicitly chose **not** to rewrite/force-push git history to "fix" an already-tagged release when a small bug was found post-tag — cut a proper patch version instead.
- Renamed default branch `master` → `main` before publishing publicly, since that's now the general convention.
- Before making the repo public: cleaned up meandering/informal commit messages (e.g. "Fixed fmt (bit Embarrassing!), again", "oh, i skip for ckv, and error was for ckv2, fixed") into conventional-commit-style messages (`feat(ci): add Checkov infrastructure security scanning`, `fix(terraform): address Checkov findings`) so the history reads as engineering work rather than a live debugging transcript. Kept a `major_errors.md` privately during development, but decided it doesn't belong in the public repo as-is — planned to move real incident content into a proper `docs/` folder instead (as was done with the OIDC incident) rather than leaving raw scratch notes in the root.
- Repo renamed mid-project from `flask-ecs-cicd-demo` to `flask-ecs-devops-pipeline` — the title decision itself mattered: settled on "Containerized Flask Deployment on AWS ECS Fargate" over a generic "Flask ECS Demo" specifically because the stronger keywords (Containerized, ECS Fargate, AWS) read better to anyone scanning repo titles.
- README structure standardized to match other featured repos in the portfolio: banner → overview/description → badges → architecture diagram → features → repo structure → infra provisioned → deployment workflow → deployment steps → screenshots → future improvements → license. Kept the same visual "banner + centered badges" style used across other projects rather than inventing a new format per repo, for portfolio consistency.
- Screenshots chosen deliberately to prove the pipeline, not just decorate the README: GitHub Actions run succeeding, ECS service deployment reaching `rolloutState=COMPLETED` with the new task-definition revision, ECR showing the pushed tag/digest, the live app responding through the ALB, and (optional bonus) CloudWatch logs showing the new task's output — chosen as the five things that together prove code-to-production traceability end to end.

---

## 7. What's explicitly parked for later (not forgotten, deliberately deferred)

HTTPS via ACM + Route53 (with HTTP→HTTPS redirect), AWS WAF in front of the ALB, ECS Auto Scaling, AWS Secrets Manager for app config, Trivy container image scanning, Gitleaks secret scanning, blue/green deployments via CodeDeploy. All of these were considered and consciously excluded from this project's scope rather than attempted and abandoned — the reasoning each time was the same: don't let one project try to demonstrate every AWS/DevSecOps capability at once.
