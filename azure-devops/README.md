# Automated PR review in Azure DevOps

Turn on **Copilot code review** so every new pull request in your Azure Repos project gets reviewed automatically, with findings posted as inline comments on the changed lines.

This uses the review criteria from [`copilot-instructions.md`](copilot-instructions.md) in this folder — a condensed version of the `dotnet-code-reviewer` agent, sized for Copilot.

---

## What you get, and what you don't

| | |
|---|---|
| ✅ | Automatic review on every new PR, no pipeline code to write |
| ✅ | Inline comments anchored to the offending lines |
| ✅ | Your review criteria, via instruction files |
| ❌ | **No `DOTNET_CODE_REVIEW.md` file** — comments only. Your local agent still produces the file. |
| ❌ | **Not your report format** — Copilot writes its own comment style. The instructions ask it to prefix severity, but the four-bullet layout is local-only. |
| ❌ | **Can't block a merge.** Copilot always leaves a *Comment* review, never *Approve* or *Request changes*, so it doesn't satisfy required-reviewer policies. |

---

## Before you start — three blockers to check

**1. You need a Project Collection Administrator.**
The organization-level toggle can only be flipped by a PCA. If that isn't you, this is a request to whoever owns the Azure DevOps organization. Nothing else works until it's on.

**2. The default Azure Pipelines agent pool must be available.**
Copilot code review runs its jobs on it. **Self-hosted pools are not supported.** If your organization disabled the default pool, you need a [Managed DevOps Pool](https://learn.microsoft.com/en-us/azure/devops/managed-devops-pools/overview) configured first.

**3. Billing is separate from your Copilot seats.**
Per Microsoft's FAQ: *"usage in Azure DevOps doesn't use AI credits from GitHub Copilot plans."* Reviews are billed as consumption against the Azure subscription linked to your DevOps organization, metered in GitHub AI credits at $0.01 each. **Set a budget alert before enabling anything** — see [Cost control](#cost-control) below.

---

## Step 1 — Enable at the organization level (PCA only)

1. Go to `https://dev.azure.com/{yourorganization}`
2. **Organization settings** → **Repos** → **Repositories**
3. Under **GitHub Copilot code review**, turn on **Allow repositories in this organization to use Copilot code review**

> **Do not use "Enable all."** That switches the feature on for every project and repository at once. Leave org-level access on, then enable one project at a time.

## Step 2 — Enable for your project (Project Administrator)

1. **Project settings** → **Repos** → **Repositories**
2. Under **GitHub Copilot code review**, turn on **Enable Copilot code review for this project**

## Step 3 — Enable for the repository (repo owner)

1. **Project settings** → **Repos** → **Repositories** → select your repository
2. On the **Settings** tab, turn on **Enable Copilot code review for pull requests in this repository**

Verify it worked: open any PR in that repo. **GitHub Copilot** should now appear in the **Reviewers** list.

## Step 4 — Turn on automatic review

Enabling the feature only makes it *available*. Automatic review is a separate switch.

**Project settings** → **Repos** → **Repositories** → your repository → **Settings** tab → under **GitHub Copilot code review**, turn on **Automatically request Copilot code review on new pull requests**.

Then choose the scope:
- **Apply to all pull requests** — every new PR in the repo
- **Apply to specific branch policies** — only PRs targeting branches you name, e.g. `main`

> To cover every repo in the project at once, use the project-level toggle instead: **Automatically request Copilot code review on new pull requests for all repositories in this project**. Repository-level settings override the project default.

## Step 5 — Install the review criteria

You have two places to put them. **Project level is recommended** if your Azure DevOps project holds only .NET repos — it applies to every repo automatically, and you can edit it without a merge.

### Option A — Project level (recommended)

Copy the contents of [`copilot-instructions.md`](copilot-instructions.md) and paste it into the custom instructions field under **Project settings** → **Repos** → **Repositories** → **GitHub Copilot code review**.

Takes effect immediately.

### Option B — Repository level

Commit the file into the repo:

```powershell
New-Item -ItemType Directory -Force ".azuredevops" | Out-Null
Copy-Item "path\to\copilot-instructions.md" ".azuredevops\copilot-instructions.md"
git add .azuredevops\copilot-instructions.md
git commit -m "Add Copilot code review instructions"
git push
```

`.github/copilot-instructions.md` works too if you prefer that location.

> **Important:** Copilot reads repository-level instruction files from the **target branch only**. Changes made inside a PR do not affect that PR's review — they take effect after merge. Project-level instructions have no such delay, which is why Option A is easier to iterate on.

### Path-scoped rules (optional)

For per-folder rules, add `*.instructions.md` files under `.azuredevops/instructions/` with an `applyTo` front matter:

```markdown
---
applyTo: "billing/**,payments/**"
---
- Flag any money arithmetic that does not use Decimal.
- Any change to a public function here must be checked against callers in `api/`.
```

A path-scoped file without `applyTo` is skipped.

---

## Cost control

**Set a budget alert first:**

1. [Azure portal](https://portal.azure.com) → the subscription linked to your DevOps organization
2. **Cost Management** → **Budgets** → **Add**
3. Under **Filters**, add **Product** = `GitHub Copilot for AzDO`
4. Set an amount and alert thresholds (e.g. 75%, 90%), add email recipients

Charges take **48 hours** to appear in the portal, so don't judge cost on the first day.

Charges carry Azure DevOps **project tags**, so if you keep one project per technology you get per-team cost attribution by grouping on that tag.

To estimate before rolling out widely, enable it on one or two repositories and watch daily usage for a week.

---

## Limits during preview

| Limit | Value |
|---|---|
| Pull request status | Must be **Active** with no merge conflicts |
| Repository size | 10 GB or less |
| Changed files per PR | 100 or fewer |
| Concurrent reviews per organization | 5 |
| Concurrent reviews per user | 2 |
| Completed reviews per merge commit | 1 |

**Copilot does not re-review when you push new commits.** To get a fresh review, click **Request** again next to **GitHub Copilot** in the Reviewers list.

---

## Data residency — check this with your compliance team

From Microsoft's FAQ:

> Data residency for GitHub Copilot doesn't align with Azure DevOps organization data residency boundaries for this preview feature. For example, if your Azure DevOps organization is hosted in the EU, Copilot code review processing might still occur in another geography, such as the United States.

So source code may be processed outside your organization's region. On the other hand, PR diffs, prompts, and responses are **not** used to train foundation models.

If data residency is a hard requirement, the alternative is a custom Azure Pipeline calling an Azure OpenAI deployment inside your own tenant and region.

---

## Preview status

This feature is in **limited preview**: no SLA, limited support, and it can change or be removed without notice. Fine as an extra reviewer; don't make it the only thing standing between bad code and `main`.

---

## Troubleshooting

**"GitHub Copilot" doesn't appear in the Reviewers list**
One of the three scopes isn't enabled. Re-check organization → project → repository in order.

**Reviews never start**
Your organization may have disabled the default Azure Pipelines pool. Check **Organization settings** → **Repos** → **Repositories** → **Compute pool**, and select a Managed DevOps Pool if one exists.

**Copilot ignores your instructions**
Confirm the file is committed to the **target branch**, not just the PR branch. Keep the file concise — long instruction files get partially overlooked. Then click **Request** again to trigger a fresh review.

**A review failed**
**Organization settings** → **Agent pools** → the pool used for reviews → find the failed job → read the raw logs.

---

## Sources

- [Get started with Copilot code review for pull requests — Azure Repos](https://learn.microsoft.com/en-us/azure/devops/repos/git/copilot-code-reviews?view=azure-devops)
- [Configure Copilot code review instructions — Azure Repos](https://learn.microsoft.com/en-us/azure/devops/repos/git/configure-copilot-code-review-instructions?view=azure-devops)
- [Troubleshoot Copilot code review](https://learn.microsoft.com/en-us/azure/devops/repos/git/copilot-code-reviews-faq?view=azure-devops)
