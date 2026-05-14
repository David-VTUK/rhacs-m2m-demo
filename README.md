# rhacs-m2m-demo

Demo repo showing `roxctl` usage using M2M (machine-to-machine) authentication with short-lived tokens.

The GitHub Action in this repo authenticates to a **RHACS Central** instance without storing any long-lived API keys. It uses the [GitHub OIDC token](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect) flow to obtain a short-lived token that is exchanged with RHACS Central's M2M endpoint, then uses that token to scan a container image with `roxctl`.

---

## How it works

```
GitHub Actions runner
       │
       │  1. Request OIDC token  (audience = "rhacs")
       ▼
GitHub OIDC provider  ──►  short-lived JWT (signed by GitHub)
       │
       │  2. POST /v1/auth/m2m/exchange  { id_token: "<jwt>" }
       ▼
RHACS Central  ──►  validates token against Machine Access config
                    maps GitHub subject claim to a RHACS role
                    returns a short-lived RHACS access token
       │
       │  3. roxctl image scan / check  (ROX_API_TOKEN=<access_token>)
       ▼
RHACS Central  ──►  scan results + policy evaluation
```

No long-lived secret is ever stored in GitHub. The RHACS access token lives only for the duration of the workflow run.

---

## Prerequisites

### 1. RHACS Central — create a Machine Access configuration

In the RHACS UI go to **Administration → Integrations → Machine Access → Create Configuration**.

| Field | Value |
|---|---|
| Name | `GitHub Actions` (or any descriptive name) |
| Token type | `GitHub Actions` |
| Audience | `rhacs` (must match the `audience` parameter in the workflow) |

Add one or more **mapping rules** to grant the incoming token a RHACS role:

| Key | Value | Role |
|---|---|---|
| `sub` | `repo:<org>/<repo>:ref:refs/heads/main` | `Continuous Integration` |
| `sub` | `repo:<org>/<repo>:*` | `Continuous Integration` |

The `sub` claim follows GitHub's [OIDC subject claim format](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect#understanding-the-oidc-token). You can use wildcards (`*`) or pin to a specific branch, tag, or environment.

> **Tip:** The `Continuous Integration` built-in role has the minimum permissions needed for `roxctl image scan` and `roxctl image check`. Create a custom role if you need finer-grained access.

### 2. GitHub repository — set a variable

Go to **Settings → Secrets and variables → Variables → New repository variable**:

| Name | Example value | Description |
|---|---|---|
| `ROX_CENTRAL_ENDPOINT` | `central.example.com:443` | Hostname and port of your RHACS Central instance |

No secrets are required.

---

## Workflow

The workflow is defined in [`.github/workflows/rhacs-image-scan.yml`](.github/workflows/rhacs-image-scan.yml).

### Triggers

| Trigger | Behaviour |
|---|---|
| `push` to `main` | Scans the image built from that commit |
| `pull_request` targeting `main` | Scans and posts a summary comment on the PR |
| `workflow_dispatch` | Manual run; prompts for the image reference |

### Inputs (manual trigger only)

| Input | Required | Default | Description |
|---|---|---|---|
| `image` | yes | — | Full image reference, e.g. `quay.io/org/app:v1.2.3` |
| `fail_on_policy_violation` | no | `true` | Whether to fail the job when RHACS policies are violated |

### Permissions

The workflow requests only the permissions it needs:

```yaml
permissions:
  contents: read
  id-token: write   # required for OIDC token issuance
  pull-requests: write  # optional; only used to post a PR comment
```

### Steps

1. **Resolve image reference** — derives the image to scan from the event (or the manual input).
2. **Get GitHub OIDC token** — calls the GitHub OIDC endpoint with `audience=rhacs`.
3. **Exchange token** — `POST /v1/auth/m2m/exchange` to get a short-lived RHACS token.
4. **Install roxctl** — downloads the CLI binary from Central so the version always matches the server.
5. **`roxctl image scan`** — produces a JSON vulnerability report saved as a workflow artifact.
6. **`roxctl image check`** — evaluates RHACS build-time policies; optionally fails the job.
7. **Upload artifact** — attaches `scan-results.json` to the workflow run (retained 30 days).
8. **PR comment** — posts a vulnerability summary table on pull requests.

---

## Customising the image reference

By default, on push/PR events the workflow scans:

```
ghcr.io/<owner>/<repo>:<commit-sha>
```

Edit the **Resolve image reference** step in the workflow to match your registry and tagging scheme:

```yaml
IMAGE_REF="quay.io/myorg/myapp:${{ github.sha }}"
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Failed to obtain OIDC token` | Missing `id-token: write` permission | Add the permission to the job or workflow |
| `M2M token exchange failed` | No matching mapping rule | Check the `sub` claim in the OIDC token against your RHACS Machine Access config |
| `roxctl: command not found` | Central unreachable during install | Verify `ROX_CENTRAL_ENDPOINT` and network connectivity from the runner |
| Policy check fails unexpectedly | RHACS policy violations | Review violations in the RHACS UI under **Violations** |

---

## References

- [RHACS Machine Access (M2M) documentation](https://docs.openshift.com/acs/operating/manage-user-access/short-lived-access-tokens.html)
- [GitHub OIDC token documentation](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [roxctl CLI reference](https://docs.openshift.com/acs/cli/getting-started-cli.html)
