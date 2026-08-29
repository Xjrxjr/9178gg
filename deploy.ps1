# deploy.ps1 - Deploy site files to GitHub Pages
# Usage:
#   1. $env:GITHUB_PAT = 'ghp_xxxxxxxxxx' (admin PAT with repo write)
#   2. cd j:\9178GG; .\deploy.ps1

param([string]$PAT = '')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11

# ---- Config ----
$OWNER  = 'Xjrxjr'
$REPO   = '9178gg'
$BRANCH = 'main'
$BASE   = "https://api.github.com/repos/$OWNER/$REPO"
$FILES  = @(
  'coach.html','admin.html','join.html','index.html',
  'join-worker.js','coaches.json','teams.json','data.json',
  'employee.html','employees.json'
)
$ROOT   = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---- Helpers ----
function To-B64([string]$s){ return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s)) }
function From-B64([string]$b){
  $b = $b -replace "`n", ''
  return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b))
}
function Hdr([string]$pat){
  return @{ 'Authorization'='token '+$pat; 'Accept'='application/vnd.github+json'; 'User-Agent'='DeployScript/1.0' }
}

function Explain([string]$body, [int]$status){
  if ($status -eq 401) { return '[HTTP 401] PAT invalid or expired. Check your GitHub Personal Access Token.' }
  if ($status -eq 403) {
    if ($body -match 'rate limit') { return '[HTTP 403] API rate limit exceeded. Try again later.' }
    return '[HTTP 403] PAT lacks repo write permission. Please ensure repo (Contents) Read and write is granted.'
  }
  if ($status -eq 404) { return "[HTTP 404] Repo not found: $OWNER/$REPO" }
  if ($status -eq 422) { return '[HTTP 422] Request invalid (SHA mismatch or bad payload).' }
  return "[HTTP $status]"
}

function ApiCall([string]$method, [string]$url, [string]$body, [hashtable]$headers){
  $params = @{ Uri=$url; Method=$method; Headers=$headers; UseBasicParsing=$true; TimeoutSec=30 }
  if ($body -and $method -ne 'GET') { $params.Body=$body; $params.ContentType='application/json; charset=utf-8' }
  try {
    $r = Invoke-WebRequest @params
    return @{ ok=$true; status=[int]$r.StatusCode; content=$r.Content }
  } catch {
    $st = 0; $rc = ''
    if ($_.Exception.Response) {
      try { $st = [int]$_.Exception.Response.StatusCode } catch {}
      try {
        $st2 = $_.Exception.Response.GetResponseStream()
        $rd = New-Object IO.StreamReader($st2)
        $rc = $rd.ReadToEnd(); $rd.Close(); $st2.Close()
      } catch {}
    }
    return @{ ok=$false; status=$st; content=$rc; error=$_.Exception.Message }
  }
}

# ---- Get PAT ----
if (-not $PAT -and $env:GITHUB_PAT) { $PAT = $env:GITHUB_PAT }
if (-not $PAT) {
  Write-Host ''
  Write-Host '========================================' -ForegroundColor Cyan
  Write-Host '   Deploy site files to GitHub Pages' -ForegroundColor Cyan
  Write-Host '========================================' -ForegroundColor Cyan
  Write-Host ''
  Write-Host 'Enter your GitHub PAT (repo write):' -ForegroundColor Yellow
  $s = Read-Host 'PAT' -AsSecureString
  $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  $PAT = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b)
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) | Out-Null
}
$PAT = $PAT.Trim()
if (-not $PAT) { Write-Host '[FAIL] No PAT provided.' -ForegroundColor Red; exit 1 }

$headers = Hdr $PAT

# ---- Verify PAT + repo ----
Write-Host ''
Write-Host '[1/3] Verifying PAT + repo connection...' -ForegroundColor Yellow
$t1 = Get-Date
$test = ApiCall 'GET' $BASE '' $headers
$ms = [int]((Get-Date)-$t1).TotalMilliseconds
if (-not $test.ok) {
  Write-Host (Explain $test.content $test.status) -ForegroundColor Red
  if ($test.error) { Write-Host "   detail: $($test.error)" -ForegroundColor DarkRed }
  exit 2
}
$repo = $test.content | ConvertFrom-Json
Write-Host "   OK: repo $($repo.full_name) (default branch: $($repo.default_branch))  ${ms}ms" -ForegroundColor Green
if ($repo.default_branch -and $repo.default_branch -ne $BRANCH) {
  Write-Host "   WARNING: using branch '$($repo.default_branch)' instead of '$BRANCH'" -ForegroundColor Yellow
  $BRANCH = $repo.default_branch
}

# ---- Deploy files ----
Write-Host ''
Write-Host "[2/3] Deploying $($FILES.Count) files..." -ForegroundColor Yellow
Write-Host ''
$ok = 0; $fail = 0; $skipped = 0
foreach ($fname in $FILES) {
  $idx = $FILES.IndexOf($fname) + 1
  Write-Host "   [$idx/$($FILES.Count)] $fname" -ForegroundColor Cyan -NoNewline
  $lp = Join-Path $ROOT $fname
  if (-not (Test-Path -LiteralPath $lp)) {
    Write-Host "  -> FAIL file not found" -ForegroundColor Red
    $fail++; continue
  }
  try { $text = Get-Content -LiteralPath $lp -Raw -Encoding UTF8 }
  catch { Write-Host "  -> FAIL read: $($_.Exception.Message)" -ForegroundColor Red; $fail++; continue }
  $size = $text.Length
  Write-Host "  ($size B)" -ForegroundColor Gray

  # existing SHA + compare
  $sha = $null; $same = $false
  $curl = "$BASE/contents/$fname`?ref=$BRANCH"
  $g = ApiCall 'GET' $curl '' $headers
  if ($g.ok -and $g.content) {
    try {
      $c = $g.content | ConvertFrom-Json
      if ($c -and $c.sha) { $sha = $c.sha }
      if ($c -and $c.content) {
        try {
          $rt = From-B64 $c.content
          if ($rt -eq $text) { $same = $true }
        } catch {}
      }
    } catch {}
  }
  if ($same) {
    Write-Host "       -> SKIP (identical content)" -ForegroundColor Gray
    $skipped++; $ok++; continue
  }
  $shaInfo = if ($sha) { "sha=$($sha.Substring(0,7))" } else { "new file" }
  Write-Host "       -> $shaInfo writing..." -ForegroundColor DarkGray

  $payload = @{ message="deploy: $fname via deploy.ps1"; content=(To-B64 $text); branch=$BRANCH }
  if ($sha) { $payload.sha = $sha }
  $json = $payload | ConvertTo-Json -Compress -Depth 5

  $t1 = Get-Date
  $p = ApiCall 'PUT' "$BASE/contents/$fname" $json $headers
  $ms2 = [int]((Get-Date)-$t1).TotalMilliseconds
  if ($p.ok) {
    Write-Host "       -> OK (${ms2}ms)" -ForegroundColor Green
    $ok++
  } else {
    Write-Host "       -> $(Explain $p.content $p.status)" -ForegroundColor Red
    if ($p.content) { Write-Host "          $($p.content.Substring(0,[Math]::Min(180,$p.content.Length)))" -ForegroundColor DarkRed }
    $fail++
  }
}

# ---- Summary ----
Write-Host ''
Write-Host '========================================' -ForegroundColor White
if ($fail -eq 0) {
  Write-Host "[3/3] DONE: $ok deployed/skipped, $skipped identical, $fail failed" -ForegroundColor Green
  Write-Host '   GitHub Pages will refresh in 1-2 minutes.' -ForegroundColor DarkGreen
  Write-Host '   Visit: https://xjrxjr.github.io/9178gg/' -ForegroundColor DarkCyan
} else {
  Write-Host "[3/3] DONE: $ok OK, $fail FAIL" -ForegroundColor Yellow
}
Write-Host '========================================' -ForegroundColor White
