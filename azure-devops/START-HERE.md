# Start here — step-by-step setup checklist

Automated code review on pull requests, Azure DevOps Server (on-premises).
Work through these in order. Roughly 90 minutes for the first repo.

Each step has a **✓ Done when** line. If that check fails, stop and fix it before moving on — every later step depends on the earlier ones.

---

# PHASE 1 — Check your agent (10 minutes)

Do this first. If the agent can't run the tools, nothing else matters.

## Step 1 — Find which agent pool your builds use

**Collection Settings → Agent pools**

Note the pool name and which machine the agent runs on. You need to log into that machine for Step 2.

**✓ Done when:** you know the pool name and can access the agent machine.

## Step 2 — Verify the agent has what it needs

Log into the agent machine and run:

```powershell
pwsh --version
node --version
git --version
curl -sS -o $null -w "%{http_code}`n" https://api.github.com
```

You need PowerShell 7+, Node.js 18+, git, and an HTTP status from the curl (any status means internet works).

If `pwsh` is missing: install [PowerShell 7](https://github.com/PowerShell/PowerShell/releases).
If `node` is missing: install [Node.js LTS](https://nodejs.org).

**✓ Done when:** all four commands return a version or status code.

---

# PHASE 2 — Set up the GitHub side (15 minutes)

## Step 3 — Create a service account for CI

Do **not** use your personal GitHub account. Every review consumes AI credits from whoever owns the token, and a personal account means CI competes with your own Copilot usage.

Create (or pick) a dedicated GitHub account and assign it a **Copilot seat** in your organization.

**✓ Done when:** the service account appears under your org's Copilot seat assignments.

## Step 4 — Enable the Copilot CLI policy

Signed in as an org admin: **GitHub → your organization → Settings → Copilot → Policies**

Find **Copilot CLI** and set it to **Enabled**.

**✓ Done when:** the Copilot CLI policy shows as enabled for your organization.

## Step 5 — Create the GitHub token

Signed in as the **service account**: **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**

| Field | Value |
|---|---|
| Token name | `azure-devops-code-review` |
| Expiration | 1 year (set a calendar reminder) |
| Repository access | Public repositories |
| Permissions | **Copilot Requests** |

Copy the token now — GitHub won't show it again.

**✓ Done when:** you have the token string saved somewhere temporary and safe.

---

# PHASE 3 — Set up the shared repo (15 minutes)

## Step 6 — Create the SharedTools repo

In the collection you're starting with:
**Repos → the repo dropdown at the top → New repository**

| Field | Value |
|---|---|
| Repository name | `SharedTools` |
| Add a README | Yes |

> One per collection. Collections are isolated on Azure DevOps Server — a repo in one collection can't be reached from another, so each collection needs its own copy.

**✓ Done when:** the `SharedTools` repo exists and you can clone it.

## Step 7 — Add the script and prompt

Clone `SharedTools`, then copy in these two files from this repo:

```
SharedTools/
├── review-prompt.md
└── scripts/
    └── Invoke-CodeReview.ps1
```

Commit and push to the default branch.

**✓ Done when:** both files are visible in the Azure DevOps web UI under `SharedTools`.

---

# PHASE 4 — Configure the project (10 minutes)

## Step 8 — Create the variable group

**Pipelines → Library → + Variable group**

| Field | Value |
|---|---|
| Variable group name | `code-review` |

Add one variable:

| Name | Value | Lock icon |
|---|---|---|
| `COPILOT_GITHUB_TOKEN` | the token from Step 5 | **click it — must be secret** |

Save.

**✓ Done when:** the group exists and the token shows as `***`.

## Step 9 — Let the build post comments

**Project settings → Repos → Repositories → All Repositories → Security tab**

Find **`<Your Project Name> Build Service`** in the user list. Set:

| Permission | Value |
|---|---|
| Contribute to pull requests | **Allow** |

Setting this on **All Repositories** covers every repo in the project at once.

**✓ Done when:** the permission reads *Allow*, not *Not set*.

---

# PHASE 5 — Build the pipeline (20 minutes)

## Step 10 — Create a classic pipeline

**Pipelines → New pipeline**

At the bottom of the "Where is your code?" page, click **Use the classic editor**.

| Field | Value |
|---|---|
| Source | Azure Repos Git |
| Team project | your project |
| Repository | `4iGAssistant` (the pilot repo) |
| Default branch | `master` |

Continue → choose **Empty job**.

**✓ Done when:** you see the pipeline editor with an "Agent job 1" row.

## Step 11 — Configure the agent job

Click the **Agent job 1** row. Set:

| Setting | Value |
|---|---|
| Agent pool | your pool from Step 1 |
| **Allow scripts to access the OAuth token** | ✅ **checked** |

That checkbox is easy to miss and the script fails without it.

**✓ Done when:** the checkbox is ticked.

## Step 12 — Turn off shallow fetch

Click the **Get sources** row at the top. Find **Shallow fetch** and make sure it is **unchecked**.

The script compares your branch against the target branch, which needs history.

**✓ Done when:** Shallow fetch is off.

## Step 13 — Add the script task

Click **+** on the Agent job row → search **PowerShell** → **Add**.

Click the new task and set:

| Field | Value |
|---|---|
| Display name | `Run code review` |
| Type | **Inline** |
| Use PowerShell Core | ✅ **checked** |

Paste this into the Script box:

```powershell
$ErrorActionPreference = 'Stop'
$tools = Join-Path $env:AGENT_TEMPDIRECTORY 'review-tools'

if (Test-Path $tools) { Remove-Item -Recurse -Force $tools }

git -c http.extraheader="AUTHORIZATION: bearer $env:SYSTEM_ACCESSTOKEN" clone --depth 1 `
    "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$($env:SYSTEM_TEAMPROJECT)/_git/SharedTools" $tools
if ($LASTEXITCODE -ne 0) { throw "Failed to clone SharedTools." }

pwsh -NoProfile -File (Join-Path $tools 'scripts/Invoke-CodeReview.ps1')
```

**✓ Done when:** the task shows in the job list with your script in it.

## Step 14 — Link the variable group

**Variables tab → Variable groups → Link variable group** → select `code-review` → **Link**.

**✓ Done when:** `code-review` is listed under Variable groups.

## Step 15 — Save

Click **Save** (the dropdown arrow next to *Save & queue* → **Save**). **Do not queue it** — it only works on a pull request.

Name it `Automated code review`.

**✓ Done when:** the pipeline appears in your Pipelines list.

---

# PHASE 6 — Attach it and test (20 minutes)

## Step 16 — Add the branch policy

**Project settings → Repos → Repositories → `4iGAssistant` → Policies → `master` → Build Validation → +**

| Field | Value |
|---|---|
| Build pipeline | `Automated code review` |
| Path filter | *(leave empty)* |
| Trigger | Automatic |
| Policy requirement | **Optional** |
| Build expiration | Immediately when `master` is updated |
| Display name | `Automated code review` |

**Optional**, not Required — the review comments but never blocks a merge. You can tighten this later once you trust it.

**✓ Done when:** the policy is listed under Build Validation.

## Step 17 — Open a test pull request

Create a branch, add something obviously wrong, and open a PR into `master`.

For a Python repo, something like:

```python
def process_items(session, items, cache={}):     # mutable default argument
    for item in items:
        try:
            handle(session, item)
        except:                                   # bare except swallows everything
            pass
```

**✓ Done when:** the PR exists and you can see the build running under the Checks section.

## Step 18 — Watch the run

**Pipelines → the running build → the job log**

The script prints each phase:

```
=== Reading pipeline context ===
=== Computing diff ===
=== Preparing Copilot CLI ===
=== Running review ===
=== Posting to pull request ===
Done.
```

If it fails, the last section printed tells you where. See the troubleshooting table in `CLASSIC-PIPELINE-SETUP.md`.

**✓ Done when:** the log ends with `Done.`

## Step 19 — Check the comment

Go back to the PR. There should be a comment with the review in your format — `Location:`, `Severity:`, `Issue:`, `Recommendation:`.

**✓ Done when:** the comment is there and reads correctly.

## Step 20 — Test the update behaviour

Push another commit to the same PR. The build runs again.

The existing comment should be **updated**, not duplicated.

**✓ Done when:** there is still exactly one review comment on the PR.

---

# PHASE 7 — Roll out (varies)

## Step 21 — Test whether one pipeline can serve many repos

Pick a second repo. **Project settings → Repos → Repositories → [second repo] → Policies → [default branch] → Build Validation → +**

Look at the **Build pipeline** dropdown. Is `Automated code review` in the list, even though it belongs to `4iGAssistant`?

- **Yes** → one pipeline covers everything. Add the policy to each repo and you're done.
- **No** → clone the pipeline per repo: **Pipelines → `Automated code review` → ⋯ → Clone**, change the source repository, save.

**✓ Done when:** you know which case applies.

## Step 22 — Apply to the remaining repos

If the answer to Step 21 was yes, script it:

```bash
PROJECT="<your project>"
PIPELINE_ID=<id from the pipeline URL>

for REPO in $(az repos list --project "$PROJECT" --query "[].name" -o tsv); do
  REPO_ID=$(az repos show --repository "$REPO" --project "$PROJECT" --query id -o tsv)
  BRANCH=$(az repos show --repository "$REPO" --project "$PROJECT" --query defaultBranch -o tsv | sed 's|refs/heads/||')

  az repos policy build create \
    --repository-id "$REPO_ID" \
    --branch "$BRANCH" \
    --build-definition-id "$PIPELINE_ID" \
    --blocking false --enabled true \
    --queue-on-source-update-only false \
    --display-name "Automated code review" \
    --project "$PROJECT"
done
```

This reads each repo's real default branch rather than assuming `main` or `master`.

## Step 23 — Watch the cost for a week

**GitHub → your organization → Settings → Billing → Copilot**

Check the service account's AI credit consumption. Your plan includes 1,900 (Business) or 3,900 (Enterprise) credits per user per month; overage is $0.01 per credit.

Set a budget control on that account once you know the real burn rate.

**✓ Done when:** you have a week of real usage data and a budget alert configured.

---

# Repeat for other collections

Each collection needs its own pass through Phases 3–6, with that language's `review-prompt.md`:

| Collection | Prompt file from |
|---|---|
| Python | `claude-code-review-agent` |
| .NET | `claude-copilot-dotnet-review-agent` |
| Angular | `claude-copilot-angular-review-agent` |

Phases 1 and 2 are done once — the agent check and the GitHub token are shared across collections.
