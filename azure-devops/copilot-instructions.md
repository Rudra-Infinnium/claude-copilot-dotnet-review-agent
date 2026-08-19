# Copilot code review instructions — ASP.NET Core services

Review ASP.NET Core Web API and microservice code. Report only issues that matter in production. Skip style, formatting, and naming unless they cause an actual bug — analyzers already cover those.

## Impact analysis

- When a method signature, return type, or thrown exceptions change, search the repository for callers and check each one still works. Name the caller's file and line in the comment.
- When a DTO, entity, or configuration binding changes, check the code that reads it.
- If a caller would break, comment on the changed method and say which caller breaks and why.

## Dependency injection and configuration

- Flag `DbContext` or any non-thread-safe service registered as `Singleton`.
- Flag captive dependencies — a longer-lived service holding a shorter-lived one.
- Flag configuration read directly from `IConfiguration` where `IOptions<T>` belongs.
- Flag secrets and connection strings committed in `appsettings.json`.

## Data access

- Flag N+1 patterns: missing `Include`, or queries inside loops.
- Flag read-only queries that omit `AsNoTracking()`.
- Flag `ToListAsync()` before the `Where` clause — filtering in memory instead of in SQL.
- Flag multi-write operations with no transaction boundary.
- Flag `FromSqlRaw` built by string interpolation.

## Async and concurrency

- Flag `.Result`, `.Wait()`, and `.GetAwaiter().GetResult()` — these block the thread pool.
- Flag `async void` outside event handlers.
- Flag missing `CancellationToken` on long-running or database operations.
- Flag `new HttpClient()` instead of `IHttpClientFactory`.

## Reliability

- Flag outbound HTTP with no timeout, retry, or circuit breaker.
- Flag missing global exception middleware — unhandled exceptions must not leak stack traces to callers.
- Flag `catch` blocks that swallow exceptions without logging or rethrowing.
- Flag non-idempotent POST endpoints that perform payments or other irreversible side effects.

## Security

- Flag controllers or endpoints missing `[Authorize]` where siblings have it.
- Flag CORS configured with `AllowAnyOrigin` outside development.
- Flag missing input validation on request models.
- Flag secrets written to logs.

## Observability

- Flag errors logged without correlation context.
- Flag missing structured logging at failure points.

## Comment style

- One issue per comment, anchored to the line it affects.
- Say what breaks and give the concrete fix. Two or three sentences maximum.
- Start every comment with its severity in bold: **Critical**, **High**, **Medium**, or **Low**.
- Critical = data loss, security hole, or outage risk. High = correctness or reliability bug. Medium = real quality issue. Low = polish.
- Do not explain what the code does or teach the underlying concept.
