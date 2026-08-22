# .NET Code Review Agent

A reusable code-review agent for **Claude Code** and **GitHub Copilot Chat** that performs a full project-wide review of an ASP.NET Core Web API / microservice and writes a structured report to `DOTNET_CODE_REVIEW.md`.

---

## Table of Contents

1. [What this agent does](#what-this-agent-does)
2. [Choose your tool](#choose-your-tool)
3. [Path A — Set up with Claude Code](#path-a--set-up-with-claude-code)
    - [A.1 Install prerequisites](#a1-install-prerequisites)
    - [A.2 Install the agent file](#a2-install-the-agent-file)
    - [A.3 Verify the agent is loaded](#a3-verify-the-agent-is-loaded)
    - [A.4 Run the review](#a4-run-the-review)
4. [Path B — Set up with GitHub Copilot Chat](#path-b--set-up-with-github-copilot-chat)
    - [B.1 Install prerequisites](#b1-install-prerequisites)
    - [B.2 Enable prompt files in VS Code](#b2-enable-prompt-files-in-vs-code)
    - [B.3 Install the prompt file](#b3-install-the-prompt-file)
    - [B.4 Switch Copilot Chat to Agent mode](#b4-switch-copilot-chat-to-agent-mode)
    - [B.5 Run the review](#b5-run-the-review)
5. [What the report looks like](#what-the-report-looks-like)
6. [Customization](#customization)
7. [Sharing with your team](#sharing-with-your-team)
8. [Troubleshooting](#troubleshooting)
9. [Related repos](#related-repos)
10. [License](#license)

---

## What this agent does

When invoked in a .NET project, the agent:

1. Discovers all C# and config files itself (`*.cs`, `*.csproj`, `Program.cs`, etc.)
2. Reads `Program.cs` (DI, connector init, `Start`), the API / SDK / fill-up layers, and the database classes
3. Reviews against **our organization's .NET connector conventions** (not generic ASP.NET Core):
   - Architecture & separation (API / SDK / fill-up layers; method summaries)
   - Database access — the mandatory `CommonDatabaseManager` pattern, `InitializeSqlParameters()`, private params, common-DLL execution, no inline SQL
   - Performance (memory/CPU, `StringBuilder`)
   - Security (no secrets in logs)
   - Observability (Serilog)
   - Code quality
   - **Ignores intentional choices:** Singleton, sequential (no async), no EF/Dapper, no `IOptions<T>`, no controllers/middleware, `DateTime.Now`
4. Writes `DOTNET_CODE_REVIEW.md` at the project root: findings by severity (Critical / High / Medium / Low) with `file:line` locations and concrete recommendations

The agent is **read-only** — it never edits your source code. The only file it writes is `DOTNET_CODE_REVIEW.md`.

---

## Choose your tool

This repo ships **two versions of the same review prompt**. Install whichever matches what you use:

| I use… | Follow… |
|---|---|
| Claude Code (terminal CLI) | [Path A](#path-a--set-up-with-claude-code) |
| GitHub Copilot Chat inside VS Code | [Path B](#path-b--set-up-with-github-copilot-chat) |
| Both | Do both paths — they don't conflict |

---

## Path A — Set up with Claude Code

### A.1 Install prerequisites

You need three things:

1. **Node.js 18 or newer** — required by the Claude Code CLI.
   - Download: https://nodejs.org/en/download
   - Verify:
     ```powershell
     node --version
     ```
2. **Claude Code CLI**
   ```powershell
   npm install -g @anthropic-ai/claude-code
   ```
   Verify:
   ```powershell
   claude --version
   ```
3. **A Claude account with access to the Opus model** (this agent is configured to use `claude-opus-4-7`). Sign in the first time you run `claude`:
   ```powershell
   claude
   ```
   Follow the browser prompt to authenticate.

### A.2 Install the agent file

The agent is a single Markdown file. You have two options for where to put it.

#### Option A — Personal install (agent available in ALL your projects)

Best if this is just for you.

**Windows / PowerShell:**
```powershell
git clone https://github.com/Rudra-Infinnium/claude-copilot-dotnet-review-agent.git
New-Item -ItemType Directory -Force "$HOME\.claude\agents" | Out-Null
Copy-Item "claude-copilot-dotnet-review-agent\.claude\agents\dotnet-code-reviewer.md" "$HOME\.claude\agents\"
```

The file now lives at `C:\Users\<you>\.claude\agents\dotnet-code-reviewer.md`. Claude Code auto-discovers everything in that folder.

#### Option B — Per-project install (ships with your project code)

Best if you want your teammates to get the agent automatically when they clone the project.

From inside your target .NET project:

```powershell
git clone https://github.com/Rudra-Infinnium/claude-copilot-dotnet-review-agent.git ..\_reviewer_tmp
New-Item -ItemType Directory -Force ".claude\agents" | Out-Null
Copy-Item "..\_reviewer_tmp\.claude\agents\dotnet-code-reviewer.md" ".claude\agents\"
Remove-Item -Recurse -Force ..\_reviewer_tmp

git add .claude\agents\dotnet-code-reviewer.md
git commit -m "Add dotnet-code-reviewer agent"
git push
```

The file now lives at `<your-project>\.claude\agents\dotnet-code-reviewer.md`. Anyone who clones this project + has Claude Code installed will see the agent.

### A.3 Verify the agent is loaded

Open Claude Code inside any .NET project:

```powershell
cd C:\path\to\your\dotnet\project
claude
```

Once the Claude prompt is ready, type:

```
/agents
```

You should see `dotnet-code-reviewer` in the list. If not, see [Troubleshooting](#troubleshooting).

### A.4 Run the review

The agent reviews the **whole project by default**, but you can narrow it — just say what you want:

| What you type | What gets reviewed |
|---|---|
| `Review this .NET project` | Everything (default) |
| `Review src/Billing/` | Just that folder |
| `Review OrderService.cs` | Just that file |
| `Review my changes` | Uncommitted work (`git diff`) |
| `Review this branch` | Your branch vs `main` — good for self-review before pushing |
| *paste a snippet* then `review this` | Just the pasted code |

You can also name the agent explicitly if auto-delegation doesn't fire:

```
Use the dotnet-code-reviewer agent to review src/Api/Controllers/
```

The agent will:
1. Work out the scope from your request
2. Read the in-scope files
3. Write `DOTNET_CODE_REVIEW.md` at the project root
4. Print a summary of finding counts and the top fix

Open `DOTNET_CODE_REVIEW.md` in VS Code / Notepad / your editor of choice to review the results.

> **Note:** narrowed reviews overwrite the same `DOTNET_CODE_REVIEW.md`. Check the `Mode:` line at the top of the report if you're unsure whether you're looking at a full or partial review.

---

## Path B — Set up with GitHub Copilot Chat

### B.1 Install prerequisites

You need:

1. **VS Code 1.90 or newer**. Check via `Help → About`.
2. **GitHub Copilot subscription** (individual, business, or enterprise). Sign in via `View → Command Palette → GitHub Copilot: Sign In`.
3. **GitHub Copilot Chat extension** in VS Code:
   - Extensions view (`Ctrl+Shift+X`) → search **"GitHub Copilot Chat"** → Install.

Verify: the Copilot Chat panel opens with `Ctrl+Alt+I` (Windows).

### B.2 Enable prompt files in VS Code

Prompt files (`.prompt.md`) are a beta feature — you must enable them once.

1. Open Command Palette: `Ctrl+Shift+P`
2. Type: **"Preferences: Open User Settings (JSON)"** → Enter
3. Add this line:
   ```json
   "chat.promptFiles": true
   ```
4. Save (`Ctrl+S`).

### B.3 Install the prompt file

Copilot prompt files must live **inside your target project** at `.github/prompts/`. They are not global.

From inside the target .NET project:

**Windows / PowerShell:**
```powershell
git clone https://github.com/Rudra-Infinnium/claude-copilot-dotnet-review-agent.git ..\_reviewer_tmp
New-Item -ItemType Directory -Force ".github\prompts" | Out-Null
Copy-Item "..\_reviewer_tmp\.github\prompts\dotnet-code-reviewer.prompt.md" ".github\prompts\"
Remove-Item -Recurse -Force ..\_reviewer_tmp

git add .github\prompts\dotnet-code-reviewer.prompt.md
git commit -m "Add dotnet-code-reviewer prompt for Copilot"
git push
```

The file now lives at `<your-project>\.github\prompts\dotnet-code-reviewer.prompt.md`. Anyone who clones this project + has Copilot Chat with `chat.promptFiles` enabled can invoke it.

### B.4 Switch Copilot Chat to Agent mode

Without Agent mode, Copilot cannot write the report file — you'll get the review as chat output only.

1. Open Copilot Chat: `Ctrl+Alt+I`
2. At the top of the chat panel, look for a **mode picker** (usually shows "Ask" or "Edit" or "Agent")
3. Select **Agent**

### B.5 Run the review

In the Copilot Chat panel, type `/dotnet-code-reviewer`. It reviews the **whole workspace by default**, but you can narrow it:

| How you invoke it | What gets reviewed |
|---|---|
| `/dotnet-code-reviewer` | Everything (default) |
| Select code in the editor first, then `/dotnet-code-reviewer` | Just the selection |
| `/dotnet-code-reviewer #file:OrderService.cs` | Just that file |
| `/dotnet-code-reviewer src/Billing/` | Just that folder |
| `/dotnet-code-reviewer my changes` | Uncommitted work (`git diff`) |
| `/dotnet-code-reviewer this branch` | Your branch vs `main` |

Press Enter. Copilot will:
1. Work out the scope
2. Ask you to approve tool calls (Read, Search, Write) — click **Continue** each time, or click **Always** to skip future prompts for that tool
3. Write `DOTNET_CODE_REVIEW.md` at the workspace root
4. Summarize the results in chat

Open `DOTNET_CODE_REVIEW.md` in the editor to review the results.

---

## What the report looks like

The generated `DOTNET_CODE_REVIEW.md` follows this structure. `Issue` and `Recommendation` are capped at 2–3 lines each so the report stays scannable:

```markdown
# .NET Code Review Report

**Date:** 2026-08-19
**Mode:** Full project
**Scope:** 18 C# files across the connector

## Executive Summary
The connector follows the API / SDK / fill-up separation well. The main gaps are a
database class that bypasses the mandatory `InitializeSqlParameters()` pattern and a
log line that could leak the connection string.

## Findings

### High

#### Hardcoded SQL in command instead of InitializeSqlParameters()
- **Location:** `src/Data/OrderDataManager.cs` line 48
- **Severity:** High
- **Issue:** The query text is written inline in the command and parameters are set
  in the method body, bypassing the single `InitializeSqlParameters()` pattern.
- **Recommendation:** Move the command text and parameters into `InitializeSqlParameters()`,
  declare the parameters `private`, and execute via the common DLL method.

#### Connection string may be written to logs
- **Location:** `src/Data/CustomerDataManager.cs` line 23
- **Severity:** High
- **Issue:** The Serilog call logs the full connection object on failure, which can
  expose the connection string and credentials.
- **Recommendation:** Log only a safe identifier; never log the connection string.

### Medium

#### String concatenation in a loop
- **Location:** `src/Fillup/ReportBuilder.cs` line 71
- **Severity:** Medium
- **Issue:** The report text is built with `+=` inside a loop, allocating a new string
  each iteration.
- **Recommendation:** Use `StringBuilder` to accumulate the text.

### Low
```

---

## Customization

Both files are Markdown with frontmatter + a system prompt. Open and edit either:

- `.claude/agents/dotnet-code-reviewer.md` (Claude Code)
- `.github/prompts/dotnet-code-reviewer.prompt.md` (Copilot)

### Claude Code frontmatter fields

| Field | What it does |
|---|---|
| `name` | Identifier used to invoke the agent |
| `description` | Text Claude reads to decide when to auto-invoke |
| `tools` | Which Claude Code tools the agent may use (read-only + Write) |
| `model` | `opus`, `sonnet`, `haiku`, or a pinned ID like `claude-opus-4-7` |

### Copilot frontmatter fields

| Field | What it does |
|---|---|
| `mode` | `agent` (can write files), `ask` (chat only), or `edit` (edits code) |
| `description` | Shown in the Copilot mode picker |

The body below the frontmatter is the prompt — adjust focus areas, output format, and rules to match your team's standards.

---

## Sharing with your team

1. Ensure teammates have access to this private repo (`Settings → Collaborators`).
2. Send them this README link.
3. For projects where you want the reviewer to ship with the code: commit `.claude/agents/dotnet-code-reviewer.md` and/or `.github/prompts/dotnet-code-reviewer.prompt.md` into that project's own repo. Teammates get them on `git pull` — no per-user setup.

---

## Troubleshooting

**`claude` command not found**
Node.js isn't installed, or the npm global bin isn't on PATH. Reinstall Node.js from https://nodejs.org and open a **new** PowerShell window.

**`/agents` doesn't list `dotnet-code-reviewer`**
- Check the file exists at `C:\Users\<you>\.claude\agents\dotnet-code-reviewer.md` (or the project's `.claude\agents\` folder).
- Check the frontmatter at the top of the file is intact (starts with `---` on line 1).
- Close and reopen Claude Code.

**Claude Code says "no access to model claude-opus-4-7"**
Your plan doesn't include Opus. Edit `.claude/agents/dotnet-code-reviewer.md` and change `model: claude-opus-4-7` to `model: sonnet`.

**Copilot `/dotnet-code-reviewer` doesn't appear as a suggestion**
- Confirm `"chat.promptFiles": true` in User Settings.
- Confirm the file is at `.github/prompts/dotnet-code-reviewer.prompt.md` in the currently open workspace.
- Reload VS Code: `Ctrl+Shift+P` → **Developer: Reload Window**.

**Copilot runs the review but doesn't write `DOTNET_CODE_REVIEW.md`**
You're not in Agent mode. Switch the Copilot Chat mode picker to **Agent** and re-run.

---

## Related repos

- Angular reviewer: [claude-copilot-angular-review-agent](https://github.com/Rudra-Infinnium/claude-copilot-angular-review-agent)
- Python reviewer: [claude-code-review-agent](https://github.com/Rudra-Infinnium/claude-code-review-agent)

---

## License

MIT — see [LICENSE](LICENSE).
