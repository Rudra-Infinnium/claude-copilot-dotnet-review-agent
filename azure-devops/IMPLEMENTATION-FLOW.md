# Implementing automated code review on Azure DevOps Server

A decision flow, grounded in what has been verified against Microsoft's documentation and what has not.

---

## Verified facts

| Fact | Evidence |
|---|---|
| **Copilot code review is Azure DevOps Services only.** Not available on Azure DevOps Server at any version. | The [docs source](https://github.com/MicrosoftDocs/azure-devops-docs/blob/main/docs/repos/git/copilot-code-reviews.md) includes `version-eq-azure-devops`, which means Services only. Prerequisites require an Azure subscription linked to the organization for consumption billing — on-prem has no such linkage. |
| **Pipeline decorators work on Azure DevOps Server.** They inject steps into every pipeline job across a collection without anyone editing YAML. | [Author a pipeline decorator](https://learn.microsoft.com/en-us/azure/devops/extend/develop/add-pipeline-decorator?view=azure-devops) — applies-to reads "Azure DevOps Services \| Azure DevOps Server \| Azure DevOps Server 2022". Docs: *"The decorator runs on every job in every pipeline in the organization."* |
| **Service hooks cannot be scoped to all repositories.** | [Service hooks events](https://learn.microsoft.com/en-us/azure/devops/service-hooks/events?view=azure-devops) — the `git.pullrequest.created` event has `repository` (guid) as a **required** filter. |
| **Branch policies, including Build Validation, exist on Server.** | [Branch policies](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies?view=azure-devops), Server monikers present. |
| **An "All Repositories → Policies" tab exists.** | [Repository settings](https://learn.microsoft.com/en-us/azure/devops/repos/git/repository-settings?view=azure-devops): *"On the Policies tab, you can define the policies for all Git repositories or for an individual repository."* |
| **The YAML `pr:` trigger does not work for Azure Repos.** PR triggering is done through Branch Policy → Build Validation. | Long-standing Azure Repos behaviour, documented in the build validation section. |

## Not verified — check these yourself

The docs do not answer these, and they differ by Server version. Your own instance is the authority.

1. Whether **Build Validation** is among the policy types offered on the All Repositories → Policies tab.
2. Whether the [Copilot Code Review extension](https://marketplace.visualstudio.com/items?itemName=LittleFortSoftware.ado-copilot-code-review) `.vsix` installs on your Server version.
3. Your Azure DevOps Server version.
4. Whether build agents have outbound internet access.

---

## Step 0 — Run three checks (about five minutes)

### Check 1 — Is Build Validation available cross-repo?

**Project Settings → Repos → Repositories → All Repositories → Policies tab.**

Look for **Build Validation** in the list of policies you can add.

### Check 2 — Do your repos already have PR build validation?

Pick two or three representative repos:
**Project Settings → Repos → Repositories → [repo] → Policies → `main`**

Is there already a Build Validation entry?

### Check 3 — Can build agents reach the internet?

From a machine in the same network as a build agent:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" https://api.githubcopilot.com
```

Any HTTP status means you got through. A timeout or connection refused means egress is blocked.

---

## Step 1 — Pick your route from the results

```
Check 3 blocked?
  └── Yes → STOP. Open egress, or host a model inside the network. See Route D.

Check 1: Build Validation available cross-repo?
  ├── Yes → Route A: one policy per project. Least work.
  └── No
      └── Check 2: do repos already have PR builds?
          ├── Yes → Route B: pipeline decorator. Collection-wide, unbypassable.
          └── No  → Route C: per-repo setup, scripted.
```

---

## Route A — Cross-repo build validation policy

**Use when** Check 1 shows Build Validation on the All Repositories Policies tab.

This is the least work by a wide margin: the policy applies to every repo in the project, including repos created later.

1. Create one pipeline that performs the review (see `azure-pipelines-review.yml` in this folder). It needs a home repo — put it in a shared `pipeline-templates` repo in the collection.
2. **Project Settings → Repos → Repositories → All Repositories → Policies → Build Validation → +**
3. Select the pipeline, set the branch to `main`, set the policy requirement to **Optional** so it comments without blocking merges.

**Caveat to confirm during setup:** a build validation pipeline normally builds the repo the PR is in. Verify the pipeline resolves the correct repo at runtime when triggered cross-repo — the extension reads PR context from `System.PullRequest.*` variables rather than the checkout, which should make this work, but test on one repo before rolling out.

---

## Route B — Pipeline decorator

**Use when** Check 1 is no and Check 2 is yes — your repos already run a build on PRs.

A decorator is a private extension installed once at the collection level. It injects your review step into every pipeline job automatically. Teams cannot remove it, because it is not in their YAML.

### B.1 — Build the extension

```
my-review-decorator/
├── vss-extension.json
└── review-decorator.yml
```

**vss-extension.json**
```json
{
  "manifestVersion": 1,
  "id": "code-review-decorator",
  "publisher": "YourPublisherId",
  "version": "1.0.0",
  "name": "Automated Code Review Decorator",
  "targets": [{ "id": "Microsoft.VisualStudio.Services" }],
  "contributions": [
    {
      "id": "code-review-injected",
      "type": "ms.azure-pipelines.pipeline-decorator",
      "targets": ["ms.azure-pipelines-agent-job.post-checkout-tasks"],
      "properties": { "template": "review-decorator.yml" }
    }
  ],
  "files": [
    { "path": "review-decorator.yml", "addressable": true, "contentType": "text/plain" }
  ]
}
```

**review-decorator.yml** — only runs on PR builds, so normal CI is unaffected:
```yaml
steps:
- ${{ if eq(variables['Build.Reason'], 'PullRequest') }}:
  - task: CopilotCodeReview@1
    displayName: 'Automated code review (injected)'
    inputs:
      githubPat: '$(GITHUB_PAT)'
      useSystemAccessToken: false
      azureDevOpsPat: '$(ADO_PAT)'
      collectionUri: '$(System.TeamFoundationCollectionUri)'
      diffOnlyReview: true
      promptFile: 'azure-devops/review-prompt.md'
      timeout: '20'
    env:
      SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```

### B.2 — Package and install

```bash
npm install -g tfx-cli
tfx extension create --manifest-globs vss-extension.json
```

**Collection Settings → Extensions → Manage extensions → Upload extension**, then install to the collection.

> Only **private** extensions can contribute pipeline decorators. Share it with your collection rather than publishing publicly.

### B.3 — Make the secrets reachable

The decorator references `$(GITHUB_PAT)` and `$(ADO_PAT)`. These must resolve in every pipeline it injects into. Options, in order of preference:

- Set them as **collection-level pipeline variables** if your Server version supports it
- Create a variable group named identically in every project and link it
- Bake the values into the decorator template (works, but stores secrets in the extension — least preferred)

Confirm this before rolling out; an unresolvable variable makes the injected step fail in every pipeline.

### B.4 — Where the prompt lives

`promptFile` is relative to the checked-out repo. Two options:

- Commit `review-prompt.md` to each repo — small, but it is per-repo work again
- Use the `prompt` input instead and embed the instructions directly in `review-decorator.yml` — fully centralised, edited in one place

The second keeps the no-per-repo-work property. Prefer it.

### Known gap

A decorator injects into pipelines that **run**. A repo with no pipeline at all is not covered. Pair this with a cross-repo policy requiring a successful build before merge, if your Server offers one, to close that gap.

---

## Route C — Per-repo setup, scripted

**Use when** Checks 1 and 2 are both no.

Per-repo work is unavoidable here, but it does not have to be manual.

### C.1 — One template repo per collection

Collections are hard isolation boundaries on Azure DevOps Server — `resources.repositories` cannot cross them. So each collection needs its own copy.

```
<collection>/SharedTools/pipeline-templates
├── code-review.yml
└── review-prompt.md
```

### C.2 — Stub in each target repo

```yaml
resources:
  repositories:
    - repository: templates
      type: git
      name: SharedTools/pipeline-templates
      ref: refs/heads/main

extends:
  template: code-review.yml@templates
```

### C.3 — Script the rollout

```bash
for REPO in $(az repos list --project "$PROJECT" --query "[].name" -o tsv); do
  PIPELINE_ID=$(az pipelines create \
    --name "code-review-$REPO" \
    --repository "$REPO" \
    --repository-type tfsgit \
    --branch main \
    --yml-path azure-devops/review.yml \
    --project "$PROJECT" \
    --query id -o tsv)

  REPO_ID=$(az repos show --repository "$REPO" --project "$PROJECT" --query id -o tsv)

  az repos policy build create \
    --repository-id "$REPO_ID" \
    --branch main \
    --build-definition-id "$PIPELINE_ID" \
    --blocking false \
    --enabled true \
    --queue-on-source-update-only false \
    --display-name "Automated code review" \
    --project "$PROJECT"
done
```

Re-run it whenever repos are added. It is not automatic coverage, but it is one command rather than clicking through a UI.

**This route is opt-in per repo.** A repo added without running the script is not reviewed. If unbypassable coverage is a requirement, Route A or B is the answer, not this one.

---

## Route D — No internet egress

If Check 3 fails, every cloud-model route is closed. Options:

- Open egress to the specific API host through your proxy — narrowest change
- Host a model inside the network (Ollama, vLLM, or a self-hosted deployment) and point the review script at it instead
- Keep reviews local — developers run the agents in their IDE, which needs no pipeline at all

---

## Shared prerequisites for Routes A, B, and C

1. **Install the extension.** Download the `.vsix` from the [marketplace](https://marketplace.visualstudio.com/items?itemName=LittleFortSoftware.ado-copilot-code-review), then **Collection Settings → Extensions → Manage extensions → Upload extension**. If the upload is rejected, the extension does not support your Server version and the fallback is a plain script calling the AI API directly.

2. **Two tokens.**

   *Azure DevOps PAT* — on-prem requires this rather than the system token:

   | Scope | Access |
   |---|---|
   | Code | Read |
   | Pull Request Threads | Read & Write |

   *GitHub fine-grained PAT* — Repository access: Public; Permission: **Copilot Requests**.

3. **GitHub org policy.** An admin must set GitHub Policies → Copilot → Copilot CLI to **Enabled everywhere**.

4. **PowerShell 7+ on every agent** that will run the task.

5. **Build Service permission.** Project Settings → Repos → Repositories → [repo] → Security → `<Project> Build Service` → **Contribute to pull requests: Allow**. Without it, posting the comment fails with a 403.

---

## Recommended order

1. Run the three checks in Step 0.
2. Install the extension and confirm it is accepted by your gallery.
3. Wire up **one repo** by hand and get a review posting on a test PR.
4. Only then pick Route A, B, or C for the rollout.

Getting one repo working first turns unknowns into facts and keeps a failed rollout cheap.
