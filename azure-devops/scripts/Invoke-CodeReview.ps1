<#
.SYNOPSIS
    Posts an AI code review as a comment on an Azure DevOps pull request.

.DESCRIPTION
    Designed to run inside an Azure Pipelines build-validation job on Azure DevOps
    Server (on-premises). Computes the PR diff, sends it to GitHub Copilot CLI along
    with the review instructions, and posts the result as a single PR comment.

    Re-running on the same PR updates the existing comment rather than adding a new
    one, so pushing more commits does not accumulate duplicates.

.NOTES
    Requires PowerShell 7+ and Node.js on the agent.

    Environment variables consumed:
      COPILOT_GITHUB_TOKEN   GitHub fine-grained PAT with the "Copilot Requests" permission
      SYSTEM_ACCESSTOKEN     Azure DevOps OAuth token (enable "Allow scripts to access
                             the OAuth token" on the agent job)
      ADO_PAT                Optional. Used instead of SYSTEM_ACCESSTOKEN if set —
                             switch to this if comment posting returns 403.
#>

[CmdletBinding()]
param(
    # Path to the review instructions. Defaults to review-prompt.md next to this script.
    [string] $PromptFile = (Join-Path $PSScriptRoot '..' 'review-prompt.md'),

    # Azure DevOps REST API version. 7.0 works on Server 2022. Drop to 6.0 for older.
    [string] $ApiVersion = '7.0',

    # Copilot model. Leave empty to use the CLI default.
    [string] $Model = '',

    # Skip the review if the diff exceeds this many characters.
    [int] $MaxDiffChars = 200000
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Marker used to find our own comment thread on re-runs. Do not change once deployed.
$script:Marker = '<!-- ai-code-review -->'

function Write-Section($Message) {
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Get-RequiredEnv($Name) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Required environment variable '$Name' is not set."
    }
    return $value
}

# --------------------------------------------------------------------------
# 1. Gather pipeline context
# --------------------------------------------------------------------------
Write-Section 'Reading pipeline context'

$collectionUri = Get-RequiredEnv 'SYSTEM_TEAMFOUNDATIONCOLLECTIONURI'
$project       = Get-RequiredEnv 'SYSTEM_TEAMPROJECT'
$repositoryId  = Get-RequiredEnv 'BUILD_REPOSITORY_ID'
$pullRequestId = [Environment]::GetEnvironmentVariable('SYSTEM_PULLREQUEST_PULLREQUESTID')

if ([string]::IsNullOrWhiteSpace($pullRequestId)) {
    Write-Host 'Not a pull request build. Nothing to review.'
    exit 0
}

$targetRef = Get-RequiredEnv 'SYSTEM_PULLREQUEST_TARGETBRANCH'
$targetBranch = $targetRef -replace '^refs/heads/', ''

Write-Host "Collection : $collectionUri"
Write-Host "Project    : $project"
Write-Host "Repository : $repositoryId"
Write-Host "PR         : $pullRequestId"
Write-Host "Target     : $targetBranch"

# Prefer an explicit PAT when supplied; otherwise use the build's OAuth token.
$adoPat = [Environment]::GetEnvironmentVariable('ADO_PAT')
if (-not [string]::IsNullOrWhiteSpace($adoPat)) {
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$adoPat"))
    $adoAuthHeader = "Basic $basic"
    Write-Host 'Auth       : ADO_PAT'
}
else {
    $systemToken = Get-RequiredEnv 'SYSTEM_ACCESSTOKEN'
    $adoAuthHeader = "Bearer $systemToken"
    Write-Host 'Auth       : SYSTEM_ACCESSTOKEN'
}

# --------------------------------------------------------------------------
# 2. Compute the diff
# --------------------------------------------------------------------------
Write-Section 'Computing diff'

git fetch --no-tags origin $targetBranch 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "git fetch of '$targetBranch' failed." }

$changedFiles = @(git diff --name-only "origin/$targetBranch...HEAD" | Where-Object { $_ })
if ($changedFiles.Count -eq 0) {
    Write-Host 'No changed files against the target branch. Nothing to review.'
    exit 0
}

Write-Host "Changed files: $($changedFiles.Count)"
$changedFiles | ForEach-Object { Write-Host "  $_" }

$diff = (git diff "origin/$targetBranch...HEAD") -join "`n"

if ($diff.Length -gt $MaxDiffChars) {
    Write-Warning "Diff is $($diff.Length) characters, over the $MaxDiffChars limit. Skipping review."
    exit 0
}

$diffPath = Join-Path ([IO.Path]::GetTempPath()) "pr-$pullRequestId.diff"
Set-Content -Path $diffPath -Value $diff -Encoding utf8
Write-Host "Diff written to $diffPath ($($diff.Length) chars)"

# --------------------------------------------------------------------------
# 3. Ensure Copilot CLI is available
# --------------------------------------------------------------------------
Write-Section 'Preparing Copilot CLI'

if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
    Write-Host 'copilot not found on PATH. Installing...'
    # NOTE: verify this package name against GitHub's install docs on first run.
    npm install -g @github/copilot 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Copilot CLI install failed.' }
}

$copilotVersion = (copilot --version 2>&1 | Out-String).Trim()
Write-Host "Copilot CLI: $copilotVersion"

# --------------------------------------------------------------------------
# 4. Run the review
# --------------------------------------------------------------------------
Write-Section 'Running review'

if (-not (Test-Path $PromptFile)) { throw "Prompt file not found: $PromptFile" }
$instructions = Get-Content -Path $PromptFile -Raw

# The diff stays in a file rather than on the command line — a large diff would
# otherwise blow past ARG_MAX.
$prompt = @"
$instructions

---

Review the pull request changes for this repository.
The unified diff of all changes is in the file: $diffPath
Files changed: $($changedFiles -join ', ')

Read that diff file, review it against the instructions above, and output ONLY the
review in the required format. Do not add any preamble, commentary, or closing remarks.
"@

$copilotArgs = @(
    '-p', $prompt
    '-s'
    '--no-ask-user'
    '--allow-tool', 'read'
    '--allow-all-paths'
)
if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $env:COPILOT_MODEL = $Model
}

$review = (& copilot @copilotArgs 2>&1 | Out-String).Trim()

if ($LASTEXITCODE -ne 0) { throw "Copilot CLI exited with code $LASTEXITCODE.`n$review" }
if ([string]::IsNullOrWhiteSpace($review)) { throw 'Copilot CLI returned no output.' }

Write-Host "Review generated ($($review.Length) chars)"

# --------------------------------------------------------------------------
# 5. Post or update the PR comment
# --------------------------------------------------------------------------
Write-Section 'Posting to pull request'

$base = "$($collectionUri.TrimEnd('/'))/$project/_apis/git/repositories/$repositoryId/pullRequests/$pullRequestId"
$headers = @{ Authorization = $adoAuthHeader; 'Content-Type' = 'application/json' }

$body = @"
$script:Marker
$review

---
*Automated review. Advisory only — it does not replace human review.*
"@

# Look for a thread we posted previously so re-runs update rather than duplicate.
$existingThreadId = $null
$existingCommentId = $null
try {
    $threads = Invoke-RestMethod -Uri "$base/threads?api-version=$ApiVersion" -Headers $headers -Method Get
    foreach ($thread in $threads.value) {
        if ($null -eq $thread.comments) { continue }
        $match = $thread.comments | Where-Object { $_.content -and $_.content.Contains($script:Marker) } | Select-Object -First 1
        if ($match) {
            $existingThreadId = $thread.id
            $existingCommentId = $match.id
            break
        }
    }
}
catch {
    Write-Warning "Could not list existing threads: $($_.Exception.Message)"
}

if ($existingThreadId) {
    Write-Host "Updating existing comment (thread $existingThreadId)"
    $payload = @{ content = $body } | ConvertTo-Json -Depth 5
    Invoke-RestMethod `
        -Uri "$base/threads/$existingThreadId/comments/$existingCommentId`?api-version=$ApiVersion" `
        -Headers $headers -Method Patch -Body $payload | Out-Null
}
else {
    Write-Host 'Creating new comment thread'
    $payload = @{
        comments = @(@{ parentCommentId = 0; content = $body; commentType = 1 })
        status   = 1   # active
    } | ConvertTo-Json -Depth 5
    Invoke-RestMethod `
        -Uri "$base/threads?api-version=$ApiVersion" `
        -Headers $headers -Method Post -Body $payload | Out-Null
}

Write-Host 'Done.' -ForegroundColor Green
