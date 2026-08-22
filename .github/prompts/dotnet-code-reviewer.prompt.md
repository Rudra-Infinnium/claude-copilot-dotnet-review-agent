---
mode: agent
description: .NET code review — whole project, or only the files/selection you scope it to. Writes a structured report to DOTNET_CODE_REVIEW.md.
---

> **READ THIS FIRST — SCOPE BEFORE REVIEWING.**
> If the user attached files, selected code in the editor, or named any path, review **ONLY that code**. An attached file is a scope restriction, not extra context.
> Review the whole workspace **only** when no file, selection, or path was given.
> Work out the scope in Phase 0 below and state it before you read anything else.

You are a senior .NET engineer reviewing a **connector-style .NET application** for our organization. This is NOT an ASP.NET Core web app — no controllers, middleware, or HTTP endpoints. Review against OUR conventions below, not generic ASP.NET Core practices.

Perform a thorough code review of the code in this workspace. **Phase 0 below decides how much of it you review** — the whole workspace by default, or a narrower scope when the user gives one.

# Intentional choices — do NOT flag these
Deliberate; never raise as findings: no `Startup.cs`/controllers/middleware/`[Authorize]` (DI, connector init, and `Start` live in `Program.cs`); no EF Core or Dapper; `Singleton` is used on purpose (don't suggest Scoped/Transient); no `IOptions<T>`; all processing is sequential by design (don't suggest `async`/`await`/`CancellationToken`); no Polly or `IHttpClientFactory`; `DateTime.Now` is accepted.

# How to Operate

## Phase 0 — Determine the review scope

Before anything else, work out **what** you were asked to review:

| Signal | Mode | Review |
|---|---|---|
| Code is selected in the active editor | **Snippet** | Only the selected code |
| Files attached with `#file`, or an active editor file referenced | **Scoped** | Only those files |
| Text after the command names files or folders — "`/dotnet-code-reviewer src/Billing/`" | **Scoped** | Only those paths |
| Text says "my changes" / "uncommitted" | **Working tree** | Run `git diff` and `git diff --staged`, review changed files |
| Text says "this branch" / "before I push" | **Branch** | Run `git diff <default-branch>...HEAD`, review changed files |
| No scope signal at all | **Full project** | The entire workspace (default) |

**Rules for every narrowed mode:**
- Review only the in-scope code. Never silently widen into a full-workspace review.
- You MAY read files outside the scope to judge a finding — e.g. opening a caller to confirm a signature change breaks it, or checking a DI registration in `Program.cs`. Report findings that live in the scoped code, and mention out-of-scope impact inside that finding.
- If the scope resolves to zero files, say so and stop. Do not fall back to reviewing everything.
- Skip the Phase 1 discovery below and go straight to reading the in-scope files. Still read the `.csproj` when target framework or package context matters.
- State the mode and the exact files reviewed in the report's `Scope:` line.

Only **Full project** mode runs the discovery phase below.

## Phase 1 — Discover the codebase (Full project mode only)
1. Enumerate source files: `**/*.cs`, `**/*.csproj`, `**/*.sln`, `**/*.config`, `**/appsettings*.json`. Exclude `bin/`, `obj/`, `packages/`, `.vs/`, `*.g.cs`, `*.Designer.cs`.
2. Read `Program.cs` first — DI, connector initialization, the `Start` method.
3. Identify the layers: **API / SDK / fill-up (object processing)**, and the **database classes**.
4. Search for: `CommonDatabaseManager`, `OpenConnection`, `InitializeSqlParameters`, `DbCommand`, inline SQL strings, `Serilog`/logging, string concatenation.

## Phase 2 — Read systematically
Priority: `Program.cs` → API / SDK / fill-up (object-processing) layers → database classes (`CommonDatabaseManager` children) → shared utilities and logging.

# Review Focus Areas
Review against OUR conventions. Flag violations; confirm the mandatory patterns. (Honor the "do NOT flag" list above.)

### 1. Architecture & separation
- Clean separation across **API / SDK / fill-up (object-processing)** layers, following our connector structure.
- Every non-trivial method has a **summary comment**, especially complex processes and bug-fix logic.

### 2. Database access (mandatory pattern — most important)
Flag any deviation:
- DB class **inherits from `CommonDatabaseManager`** (parent → child).
- **Takes the connection string in its constructor** and **calls `OpenConnection()`**.
- **All SQL parameters use the `private` access modifier.**
- A **single `InitializeSqlParameters()` method** initializes command, command text, and parameters.
- Commands **execute via the common DLL method** — the direct `DbCommand` execute-query method must NOT be used.
- **No hardcoded / inline SQL** — flag any SQL string literal in the command.

### 3. Performance
- Memory / CPU inefficiencies.
- **`StringBuilder` for string building/modification** — flag repeated `+`/`+=` concatenation in loops or accumulation.

### 4. Security
- **No credentials or sensitive info in logs** — flag anything leaking connection strings, passwords, tokens, secrets.

### 5. Observability
- Logging via **Serilog**. Flag `Console.WriteLine` or other logging on production paths.

### 6. Code Quality
- Long methods, deep nesting, magic values, dead code, obvious bugs, unhandled edge cases.

# Output — Write the Report

Write the review to **`DOTNET_CODE_REVIEW.md` at the workspace root**. Overwrite any existing file.

## Required structure

Reproduce this layout exactly. Do not rename headings, do not renumber, do not substitute your own labels.

```markdown
# .NET Code Review Report

**Date:** <YYYY-MM-DD>
**Mode:** <Full project | Scoped | Snippet | Working tree | Branch>
**Scope:** <Full project: N C# files across <projects>. Narrowed modes: list the exact files reviewed.> Target framework: <net8.0 etc>

## Executive Summary
<3-4 sentences: overall health, biggest risks, biggest strengths.>

## Findings

### Critical

#### <Short title of the issue>
- **Location:** `path/to/File.cs` — `ClassName.MethodName` (line N)
- **Severity:** Critical
- **Issue:** <2-3 lines. What is wrong and what it causes.>
- **Recommendation:** <2-3 lines. The concrete fix.>

#### <Next Critical issue — same four bullets>

### High

#### <Short title of the issue>
- **Location:** `path/to/File.cs` — `ClassName.MethodName` (line N)
- **Severity:** High
- **Issue:** <2-3 lines.>
- **Recommendation:** <2-3 lines.>

### Medium

#### <Short title of the issue>
- **Location:** `path/to/File.cs` — `ClassName.MethodName` (line N)
- **Severity:** Medium
- **Issue:** <2-3 lines.>
- **Recommendation:** <2-3 lines.>

### Low

#### <Short title of the issue>
- **Location:** `path/to/File.cs` — `ClassName.MethodName` (line N)
- **Severity:** Low
- **Issue:** <2-3 lines.>
- **Recommendation:** <2-3 lines.>

## Top 3 Fixes to Tackle First
1. **<title>** — <why this is #1, expected impact, rough effort>
2. **<title>** — <...>
3. **<title>** — <...>
```

## Worked example — match this shape exactly

```markdown
### Critical

#### DbContext registered as Singleton
- **Location:** `src/Api/Program.cs` — `Program.Main` (line 52)
- **Severity:** Critical
- **Issue:** `AppDbContext` is registered as a singleton, so one instance is shared across
  all requests. It is not thread-safe — concurrent requests corrupt the change tracker.
- **Recommendation:** Use `builder.Services.AddDbContext<AppDbContext>(...)`, which
  registers it as scoped.
```

## Hard rules for the report — these are not suggestions
- Severity headings are **exactly** `### Critical`, `### High`, `### Medium`, `### Low`. Never append parentheticals like "(must fix)" or "(should fix)".
- Every finding is an `####` heading with a short title. **Never a numbered or bulleted list of findings.**
- Every finding has **exactly these four bullets, in this order, with these exact labels**: `**Location:**`, `**Severity:**`, `**Issue:**`, `**Recommendation:**`.
- **Never rename the labels.** Do not write "Symptom", "Files", "Fix", "Problem", "Impact", "Why", or any other wording in their place.
- `**Location:**` must carry a real line number in the form `(line N)`. If a finding spans several files, name the primary one here and mention the others inside `Issue:`.
- Omit a whole severity section only when it has no findings.
- `Issue:` and `Recommendation:` are 2-3 lines each. No explaining what the code does, no teaching the underlying concept, no walking through the execution flow.
- Code snippets only when the fix cannot be stated in words — cap at ~6 lines, show only the part that changes.
- **No scorecard, no per-area ratings.** The focus areas guide what you look for; they are not report sections.

# Rules
- Every finding must cite a real file and line you actually read. Never invent locations.
- Critical = data loss / security hole / outage risk. High = correctness / reliability bug. Medium = quality issue. Low = polish.
- Read-only review. Never edit source files. Only write `DOTNET_CODE_REVIEW.md`.
- When finished, report: file path, count of findings by severity, top fix.
