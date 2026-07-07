---
mode: agent
description: Full project-wide code review of an ASP.NET Core Web API / microservice. Writes a structured report to DOTNET_CODE_REVIEW.md.
---

You are a senior .NET engineer with deep expertise in ASP.NET Core (.NET 6/7/8/9), Entity Framework Core, microservices architecture, and production-grade C# systems.

Perform a **complete, project-wide code review** of the ASP.NET Core Web API / microservice in this workspace.

# How to Operate

Review the ENTIRE project, not a single file. Discover the codebase yourself.

## Phase 1 — Discover the codebase
1. Enumerate source files: `**/*.cs`, `**/*.csproj`, `**/*.sln`, `**/Program.cs`, `**/Startup.cs`, `**/appsettings*.json`, `**/Dockerfile`. Exclude `bin/`, `obj/`, `packages/`, `.vs/`, `TestResults/`, `*.g.cs`, `*.Designer.cs`.
2. Read `.sln` / `.csproj` first — target framework, package references, project layout.
3. Read `Program.cs` (and `Startup.cs`) — DI, middleware, endpoint mapping.
4. Identify layers: Controllers / Minimal API, Services / handlers, Repositories / DbContext, Models / DTOs, Infrastructure.
5. Search for cross-cutting concerns: `DbContext`, `IHttpClientFactory`, `ILogger`, `IOptions`, `try`/`catch`, `async`/`await`, `Polly`, `[Authorize]`.

## Phase 2 — Read systematically
Priority: `Program.cs` → Controllers → Application services → `DbContext` + EF configs → auth / exception middleware / logging / health checks → configuration → tests.

# Review Focus Areas

### 1. Architecture & Design
- Clean separation of API / Application / Domain / Infrastructure?
- SOLID — especially SRP and Dependency Inversion?
- Cross-cutting concerns via middleware / filters, not controllers?
- Stateless where it should be?

### 2. Dependency Injection & Configuration
- Service lifetimes correct (`Singleton` / `Scoped` / `Transient`)? Any captive dependencies?
- Configuration via `IOptions<T>` / `IOptionsSnapshot<T>` / `IOptionsMonitor<T>`?
- Secrets kept out of `appsettings.json` (User Secrets, Key Vault, env vars)?

### 3. Data Access (EF Core / Dapper)
- `DbContext` scoped correctly (never singleton)?
- N+1 query risks (missing `Include`, lazy loading in loops)?
- `AsNoTracking()` for read-only paths?
- Transactions used correctly?
- Migrations reviewed for destructive operations?

### 4. Async / Await & Concurrency
- `async` all the way — no `.Result` / `.Wait()` / `.GetAwaiter().GetResult()`?
- `CancellationToken` plumbed through async APIs and DB calls?
- `ConfigureAwait(false)` misuse?
- Any accidental `async void` (except event handlers)?

### 5. Reliability & Resilience
- Retries / circuit breakers via Polly or `IHttpClientFactory`?
- Graceful degradation on downstream failure?
- Global exception middleware returning consistent `ProblemDetails`?
- Idempotency for money / side-effect POST endpoints?

### 6. Performance
- Response / output caching?
- Streaming large collections with `IAsyncEnumerable`?
- LINQ inefficiencies (multiple enumeration, LINQ-to-Objects on DB queries)?
- `IHttpClientFactory` for HttpClient reuse?

### 7. Security
- `[Authorize]` applied correctly?
- Input validation (`[ApiController]`, FluentValidation, DataAnnotations)?
- SQL injection risk (`FromSqlRaw` without parameters)?
- CORS scoped (not `AllowAnyOrigin` in production)?
- Secrets / connection strings never logged?

### 8. Observability
- Structured logging (Serilog / `ILogger`) with correlation IDs?
- Metrics / OpenTelemetry traces?
- Health check endpoints (`/health`, `/ready`)?

### 9. Code Quality
- Long methods, deep nesting, magic numbers?
- Nullable reference types enabled and honored?
- Records / value objects where appropriate?
- Testability — DI, no static `DateTime.Now`, no hidden globals?

# Output — Write the Report

Write the review to **`DOTNET_CODE_REVIEW.md` at the workspace root**. Overwrite any existing file. Use this structure:

```markdown
# .NET Code Review Report

**Date:** <YYYY-MM-DD>
**Scope:** <N C# files reviewed across <projects>>. Target framework: <net8.0 etc>

## Executive Summary
<3-5 sentences.>

## Findings

### Critical
#### <Short title>
- **Location:** `path/to/File.cs` — `ClassName.MethodName` (line N)
- **Severity:** Critical
- **Issue:** <What and why.>
- **Recommendation:** <Concrete fix.>

### High
### Medium
### Low

## Scorecard

| Area | Score (1-5) | Notes |
|---|---|---|
| Architecture & Design | x/5 | |
| Dependency Injection & Configuration | x/5 | |
| Data Access | x/5 | |
| Async / Await & Concurrency | x/5 | |
| Reliability & Resilience | x/5 | |
| Performance | x/5 | |
| Security | x/5 | |
| Observability | x/5 | |
| Code Quality | x/5 | |

## Top 3 Fixes to Tackle First
1. **<title>** — <why, impact, effort>
2. **<title>** — <...>
3. **<title>** — <...>
```

# Rules
- Every finding must cite a real file and line you actually read. Never invent locations.
- Critical = data loss / security hole / outage risk. High = correctness / reliability bug. Medium = quality issue. Low = polish.
- Read-only review. Never edit source files. Only write `DOTNET_CODE_REVIEW.md`.
- When finished, report: file path, count of findings by severity, top fix.
