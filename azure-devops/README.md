# Automated PR review on Azure DevOps Server (on-premises)

Post an AI code review as a comment on every pull request, using your existing review criteria and report format.

## Why not the built-in Copilot code review

Microsoft's Copilot code review for Azure Repos is **Azure DevOps Services only**. It is not available on Azure DevOps Server at any version.

Proof:
- The [documentation source](https://github.com/MicrosoftDocs/azure-devops-docs/blob/main/docs/repos/git/copilot-code-reviews.md) includes `version-eq-azure-devops`, which in Microsoft's docs versioning means Services only. Pages covering on-prem use `version-gt-eq-2022` or similar.
- Its prerequisites require *"An Azure subscription linked to your Azure DevOps organization"* for consumption billing. On-prem has no such linkage.
- On an on-prem collection, **Collection Settings → Repos → Repositories** shows no "GitHub Copilot code review" section at all — the feature is absent, not permission-gated.

So this folder uses a different route.

## What this uses

The [Copilot Code Review](https://marketplace.visualstudio.com/items?itemName=LittleFortSoftware.ado-copilot-code-review) extension by Little Fort Software ([source](https://github.com/little-fort/ado-copilot-code-review)) — free, open source, and explicitly supports Azure DevOps Server via PAT authentication.

It runs as a pipeline task, drives either GitHub Copilot CLI or Claude Code CLI, and posts the result as a comment on the pull request.

| | |
|---|---|
| ✅ | Comment on the PR, using **your exact report format** (via `promptFile`) |
| ✅ | Uses your existing **GitHub Copilot subscription** — no new AI billing |
| ✅ | Reviews **only the PR diff** (`diffOnlyReview`) |
| ✅ | Works on **Azure DevOps Server** |
| ❌ | General PR comments only — no inline annotations on individual lines |
| ❌ | Third-party extension — review it before adopting |

## Files in this folder

| File | Purpose |
|---|---|
| `review-prompt.md` | The review instructions and output format. Points the AI at your criteria and locks the report structure. |
| `azure-pipelines-review.yml` | The pipeline. Copy into your target repo and edit the marked values. |

---

## Prerequisites

**1. Your build agent must reach the internet.** The task downloads a CLI and calls an AI service. Test from the agent machine:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" https://api.githubcopilot.com
```

Any HTTP response means you got through. A timeout means egress is blocked and none of this will work until that's resolved.

**2. PowerShell 7+ on the agent.** The task requires `pwsh`. Check with `pwsh --version`.

**3. GitHub organization policy.** An org admin must set **GitHub Policies → Copilot → Copilot CLI** to **Enabled everywhere**, or the CLI will be refused.

---

## Step 1 — Install the extension

Azure DevOps Server uses its own extension gallery, separate from the cloud marketplace.

1. Download the extension `.vsix` from the [marketplace page](https://marketplace.visualstudio.com/items?itemName=LittleFortSoftware.ado-copilot-code-review) (**Get it free** → **Download**)
2. In your collection: **Collection Settings** → **Extensions** → **Browse local extensions** → **Manage extensions** → **Upload extension**
3. Upload the `.vsix`, then install it to your collection

> If the upload is rejected, the extension may not declare Server compatibility. Fall back to a custom pipeline script — ask and I'll write one.

## Step 2 — Create the two tokens

### Azure DevOps PAT (on-prem requires this — the system token isn't enough)

**User settings → Personal access tokens → New Token**, with scopes:

| Scope | Access |
|---|---|
| Code | Read |
| Pull Request Threads | Read & Write |
| Work Items | Read *(only if you set `includeWorkItems: true`)* |

### GitHub PAT (for Copilot CLI)

On GitHub: **Settings → Developer settings → Personal access tokens → Fine-grained tokens**

| Setting | Value |
|---|---|
| Repository access | Public repositories |
| Permission | **Copilot Requests** |

## Step 3 — Store them as pipeline secrets

**Pipelines → Library → + Variable group**, named `code-review`:

| Name | Value | Secret |
|---|---|---|
| `GITHUB_PAT` | your GitHub fine-grained token | ✅ |
| `ADO_PAT` | your Azure DevOps PAT | ✅ |

Click the padlock on each so they're stored encrypted.

## Step 4 — Add the files to your target repo

Copy both files from this folder into the repository you want reviewed:

```powershell
New-Item -ItemType Directory -Force "azure-devops" | Out-Null
Copy-Item "path\to\review-prompt.md" "azure-devops\"
Copy-Item "path\to\azure-pipelines-review.yml" "azure-devops\"
```

Then edit `azure-pipelines-review.yml`:

- `pool: name:` — your self-hosted agent pool name
- `collectionUri:` — your server URI, e.g. `https://tfs.infinnium.com/tfs/INFProjectCollection`
- `model:` — check the extension docs for the current list

Commit and push to your **default branch**. The pipeline must exist on the target branch to be selectable as a policy.

## Step 5 — Create the pipeline

**Pipelines → New pipeline → Azure Repos Git** → your repo → **Existing Azure Pipelines YAML file** → select `/azure-devops/azure-pipelines-review.yml` → **Save** (not *Save and run*).

## Step 6 — Grant the build identity permission to comment

Without this, posting the comment returns 403 with a confusing error.

**Project settings → Repos → Repositories** → your repo → **Security** tab → find **`<Project Name> Build Service`** → set **Contribute to pull requests** to **Allow**.

## Step 7 — Wire it to pull requests

The YAML `pr:` trigger does not work for Azure Repos. Use a branch policy instead:

**Project settings → Repos → Repositories** → your repo → **Policies** → select your target branch (e.g. `main`) → **Build Validation** → **+**

| Setting | Value |
|---|---|
| Build pipeline | the pipeline from Step 5 |
| Trigger | Automatic |
| Policy requirement | **Optional** |
| Build expiration | Immediately when `main` is updated |

> Set it to **Optional**, not Required. Optional means the review runs and comments but never blocks a merge — which is what you want while you're building trust in the findings. Switch to Required later if you decide a failed review should gate merges.

## Step 8 — Test it

Open a pull request with a deliberate problem — an unclosed DB session, a bare `except:`. Within a few minutes a comment should appear on the PR in your report format.

---

## Customising the review

Everything about what gets reviewed and how it's reported lives in **`review-prompt.md`**. Edit that file, commit it, and the next review picks it up.

Unlike Microsoft's Copilot code review, there's no target-branch delay here — the prompt file is read from the checked-out branch at build time.

## Cost

The GitHub Copilot CLI path bills against your existing Copilot subscription rather than a separate meter. Whether it consumes premium requests isn't documented by the extension — **watch your Copilot usage for the first week** and confirm the rate is acceptable before enabling on busy repos.

If you switch to the Claude Code CLI path, that's a separate Anthropic API bill, but the `maxBudget` input caps spend per review.

## Troubleshooting

**403 when posting the comment** — the Build Service identity lacks *Contribute to pull requests* (Step 6), or the ADO PAT is missing the *Pull Request Threads: Read & Write* scope.

**"pwsh not found"** — install PowerShell 7 on the agent.

**Copilot CLI refuses to run** — the GitHub org policy for Copilot CLI isn't enabled (Prerequisites, item 3).

**The review ignores your prompt file** — check the `promptFile` path is relative to the repo root and that the file is committed on the PR's source branch.

**Nothing runs on a PR** — the branch policy isn't attached, or it's on the wrong target branch. Check **Policies** on the branch the PR targets, not the source branch.

---

## Sources

- [Copilot Code Review extension — marketplace](https://marketplace.visualstudio.com/items?itemName=LittleFortSoftware.ado-copilot-code-review)
- [Extension source and docs](https://github.com/little-fort/ado-copilot-code-review)
- [Copilot code review for Azure Repos — Microsoft Learn](https://learn.microsoft.com/en-us/azure/devops/repos/git/copilot-code-reviews?view=azure-devops) (Services only)
