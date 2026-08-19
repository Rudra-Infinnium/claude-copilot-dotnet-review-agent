# Classic pipeline setup — no files in developer repos

Automated PR review on Azure DevOps Server, using a **classic pipeline** so nothing is committed to the repositories being reviewed.

## How it works

```
PR opened on repo X
      ↓
Branch policy (Build Validation) fires the classic pipeline
      ↓
Pipeline checks out repo X at the PR merge commit
      ↓
Inline bootstrap clones SharedTools and runs Invoke-CodeReview.ps1
      ↓
Script computes the diff, sends it to Copilot CLI with review-prompt.md
      ↓
Script posts the review as one comment on the PR
```

The only thing in the pipeline definition is a ~10-line bootstrap. The real script and the review prompt live in one `SharedTools` repo per collection, so changing the review criteria is a single commit.

## What is verified and what is not

**Verified against GitHub's documentation:**

| | |
|---|---|
| `copilot -p "PROMPT" -s` runs non-interactively and outputs only the response | [programmatic reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-programmatic-reference) |
| Auth reads `COPILOT_GITHUB_TOKEN`, then `GH_TOKEN`, then `GITHUB_TOKEN` | same |
| `--allow-tool`, `--allow-all-paths`, `--no-ask-user` control headless permissions | same |
| Output capture pattern `result=$(copilot -p "..." -s)` | [run programmatically](https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/run-cli-programmatically) |
| **Copilot CLI consumes AI credits based on tokens processed** | [about Copilot CLI](https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli) |

**Not verified — confirm during setup:**

1. **The npm package name.** The script uses `npm install -g @github/copilot`, which is what the [Little Fort extension](https://github.com/little-fort/ado-copilot-code-review) uses. GitHub's docs link to an install page that could not be retrieved. Check the CLI installs before relying on it.
2. **Token scopes.** A fine-grained GitHub PAT with the **Copilot Requests** permission is what the extension documents. Not confirmed in GitHub's own docs.
3. **Copilot CLI org policy.** May need enabling at GitHub Policies → Copilot → Copilot CLI.
4. **REST API version.** The script defaults to `7.0`, which works on Server 2022. Older Server versions need `6.0` — pass `-ApiVersion 6.0`.
5. **Whether `SYSTEM_ACCESSTOKEN` is sufficient for posting comments on your Server.** The script prefers `ADO_PAT` when set. If posting returns 403, set that variable.

---

## Step 1 — Create the SharedTools repo

One per collection (collections are isolated; a repo in one is unreachable from another).

```
SharedTools/
├── review-prompt.md                  ← the review criteria and output format
└── scripts/
    └── Invoke-CodeReview.ps1         ← the review script
```

Copy both from this folder. Push to the repo's default branch.

## Step 2 — Agent prerequisites

On every agent that will run this:

- **PowerShell 7+** — check with `pwsh --version`
- **Node.js 18+** — check with `node --version`
- **Outbound HTTPS** to GitHub — already confirmed working

## Step 3 — Create the GitHub PAT

GitHub → **Settings → Developer settings → Personal access tokens → Fine-grained tokens**

| Setting | Value |
|---|---|
| Repository access | Public repositories |
| Permission | **Copilot Requests** |

## Step 4 — Create the variable group

**Pipelines → Library → + Variable group**, named `code-review`:

| Name | Value | Secret |
|---|---|---|
| `COPILOT_GITHUB_TOKEN` | the GitHub fine-grained PAT | ✅ |
| `ADO_PAT` | *(leave unset initially — only add if you hit a 403)* | ✅ |

One variable group per project.

## Step 5 — Build the classic pipeline

**Pipelines → New pipeline → "Use the classic editor" → Azure Repos Git**

1. Pick any repo as the source (it gets overridden per-repo when the policy runs) and continue
2. Start with an **Empty job**

### Agent job settings

Open the agent job (the row above the tasks) and set:

- **Agent pool**: your self-hosted pool
- ✅ **Allow scripts to access the OAuth token** — required, or `SYSTEM_ACCESSTOKEN` is empty
- **Clean**: `true`

### Get sources

- **Shallow fetch**: **disabled**. The script needs history to compute the diff against the target branch.

### Add one task: PowerShell

**Add task → PowerShell**, then:

- **Type**: Inline
- **Script**:

```powershell
$ErrorActionPreference = 'Stop'
$tools = Join-Path $env:AGENT_TEMPDIRECTORY 'review-tools'

if (Test-Path $tools) { Remove-Item -Recurse -Force $tools }

git -c http.extraheader="AUTHORIZATION: bearer $env:SYSTEM_ACCESSTOKEN" clone --depth 1 `
    "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$($env:SYSTEM_TEAMPROJECT)/_git/SharedTools" $tools
if ($LASTEXITCODE -ne 0) { throw "Failed to clone SharedTools." }

pwsh -NoProfile -File (Join-Path $tools 'scripts/Invoke-CodeReview.ps1')
```

- ✅ **Use PowerShell Core** (so it runs under `pwsh`, not Windows PowerShell)

### Variables

**Variables tab → Variable groups → Link variable group** → `code-review`.

### Save

**Save**, not *Save and queue*. Name it something like `Automated code review`.

## Step 6 — Grant the build identity permission to comment

Without this, posting returns 403.

**Project settings → Repos → Repositories → [repo] → Security** → find **`<Project Name> Build Service`** → set **Contribute to pull requests** to **Allow**.

To cover every repo at once, set it on the **All Repositories** Security tab instead.

## Step 7 — Attach it to a repo

**Project settings → Repos → Repositories → [repo] → Policies → [your default branch] → Build Validation → +**

| Setting | Value |
|---|---|
| Build pipeline | `Automated code review` |
| Path filter | *(leave empty)* |
| Trigger | Automatic |
| Policy requirement | **Optional** |
| Build expiration | Immediately when the branch is updated |

> **Optional**, not Required — the review comments but never blocks a merge. Change it later if you decide a failed review should gate.

> Your default branch is `master` on at least some repos, not `main`. Set the policy on the branch that PRs actually target.

## Step 8 — Test

Open a PR containing a deliberate problem. Within a few minutes a comment should appear.

If it doesn't, open the pipeline run and read the logs — the script prints each phase (`=== Computing diff ===` and so on) so you can see where it stopped.

---

## Rolling out to more repos

For each additional repo, only **Step 7** is needed — attach the same pipeline as a build validation policy. Nothing is committed to the repo.

**A caveat worth testing before you rely on it:** whether the Build Validation pipeline picker lists pipelines whose source is a *different* repo. If it only offers pipelines belonging to that repo, you will need one cloned pipeline definition per repo (**Pipelines → [pipeline] → ⋯ → Clone**), changing only the source repo each time. Still no files in developer repos, but more setup.

Test this on your second repo before planning the wider rollout.

### Scripting the rollout

```bash
PIPELINE_ID=<id of the classic pipeline>
PROJECT="<your project>"

for REPO in $(az repos list --project "$PROJECT" --query "[].name" -o tsv); do
  REPO_ID=$(az repos show --repository "$REPO" --project "$PROJECT" --query id -o tsv)
  BRANCH=$(az repos show --repository "$REPO" --project "$PROJECT" --query defaultBranch -o tsv | sed 's|refs/heads/||')

  az repos policy build create \
    --repository-id "$REPO_ID" \
    --branch "$BRANCH" \
    --build-definition-id "$PIPELINE_ID" \
    --blocking false \
    --enabled true \
    --queue-on-source-update-only false \
    --display-name "Automated code review" \
    --project "$PROJECT"
done
```

This reads each repo's actual default branch rather than assuming `main` or `master`.

**This is still opt-in per repo.** A repo added later is not reviewed until the policy is applied. If unbypassable coverage matters, re-run this script on a schedule, or revisit the pipeline decorator route in `IMPLEMENTATION-FLOW.md`.

---

## Cost

Copilot CLI consumes **AI credits based on tokens processed**. Your paid seats already include an allowance, so reviews may cost nothing extra — it depends on how much of that pool you already use.

| Plan | Cost | AI credits included, per user per month |
|---|---|---|
| Copilot Business | $19/user | 1,900 |
| Copilot Enterprise | $39/user | 3,900 |
| Overage beyond the pool | | $0.01 per credit |

Code completions are **not** billed in AI credits and stay unlimited on paid plans. Only agentic usage such as the CLI draws credits.

### Use a dedicated service account

**AI credits are allocated per user.** Every CI review runs under whoever owns `COPILOT_GITHUB_TOKEN`, so all reviews across every repo draw from that one account's allowance.

Give a service account its own Copilot seat and issue the PAT from it. Two reasons:

- A developer's PAT would make CI compete with their own Copilot usage for the same credits
- A dedicated account makes CI consumption measurable in isolation

Set a budget control on that account — available at user, cost center, and enterprise level — so overage cannot run away.

### Per-review cost is unknown until measured

GitHub's documentation states credits scale with tokens processed but publishes no conversion rate. Run this on one repo for a week and read the actual consumption before rolling out.

The script caps exposure two ways:

- Only the PR diff is sent, never the whole repository
- Diffs over 200,000 characters are skipped (`-MaxDiffChars`)

Sources: [individual plans](https://docs.github.com/en/copilot/concepts/billing/individual-plans), [organization and enterprise plans](https://docs.github.com/en/copilot/concepts/billing/organizations-and-enterprises), [about Copilot CLI](https://docs.github.com/en/copilot/concepts/agents/about-copilot-cli).

## Changing the review criteria

Edit `review-prompt.md` in `SharedTools` and push. Every repo picks it up on the next PR — the bootstrap clones the repo fresh on each run.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `SYSTEM_ACCESSTOKEN is not set` | "Allow scripts to access the OAuth token" is unchecked on the agent job |
| 403 posting the comment | Build Service lacks *Contribute to pull requests* (Step 6). If that is already set, add `ADO_PAT` to the variable group |
| `git fetch of 'master' failed` | Shallow fetch is enabled in Get sources — disable it |
| `Copilot CLI install failed` | Node.js missing, or the package name has changed — check GitHub's current install docs |
| Copilot returns nothing | Token lacks the Copilot Requests permission, or the org policy for Copilot CLI is disabled |
| `api-version` errors | Older Server — pass `-ApiVersion 6.0` in the bootstrap's `pwsh` call |
| Duplicate comments on each push | The marker comment was edited or deleted; the script looks for `<!-- ai-code-review -->` |
