# Foolproof quickstart for pike-valkey-client (Windows).
# Checks Pike, ensures a local Valkey on 127.0.0.1:6379, runs the demo.
# Safe: only reads/writes demo keys on a throwaway test server.
# Run:  powershell -ExecutionPolicy Bypass -File quickstart.ps1

$ErrorActionPreference = 'Stop'

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
function Ok($msg) { Write-Host "ok: $msg" -ForegroundColor Green }

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

# 1. Pike 9
try { $pikeCmd = Get-Command pike -ErrorAction Stop } catch {
  Fail 'pike not found. Install Pike 9 first: https://pike.lysator.liu.se/download/'
}
$ver = (& pike --dumpversion 2>$null).Trim()
if (-not $ver.StartsWith('9')) { Fail "need Pike 9, found: $ver" }
Ok "pike $ver"

# 2. Local Valkey on 6379?
function Test-Port {
  try {
    $c = New-Object Net.Sockets.TcpClient('127.0.0.1', 6379)
    $c.Close()
    return $true
  } catch { return $false }
}

if (Test-Port) {
  Ok 'valkey already on 127.0.0.1:6379'
} else {
  try { $null = Get-Command docker -ErrorAction Stop } catch {
    Fail 'nothing on 127.0.0.1:6379 and no docker. Start any Valkey/Redis on 6379, then rerun.'
  }
  $names = docker ps -a --format '{{.Names}}' 2>$null
  if ($names -contains 'valkey-test') {
    docker start valkey-test >$null 2>&1
    if ($LASTEXITCODE -ne 0) { Fail 'could not start existing valkey-test container' }
  } else {
    docker run -d --name valkey-test -p 6379:6379 valkey/valkey:latest >$null 2>&1
    if ($LASTEXITCODE -ne 0) { Fail 'could not start valkey/valkey container' }
  }
  $ready = $false
  for ($i = 0; $i -lt 30; $i++) {
    if (Test-Port) { $ready = $true; break }
    Start-Sleep -Seconds 1
  }
  if (-not $ready) { Fail 'valkey still not reachable on 6379' }
  Ok 'started local valkey (docker valkey-test)'
}

# 3. Run the demo
$out = (& pike "-M$Root" (Join-Path $Root 'examples\basic.pike') 2>&1)
if ($LASTEXITCODE -ne 0) { Fail "demo failed to run: $out" }
if (-not ($out -match 'still alive: PONG')) { Fail "demo did not complete, got: $out" }
$out
Ok 'demo passed'

Write-Host ''
Write-Host 'Next:'
Write-Host '  pike -M. tests/smoke.pike            # 46 checks against live Valkey (uses db 15)'
Write-Host '  pike -M. tests/stress.pike 127.0.0.1 6379 3000'
Write-Host '  pike -M. tests/concurrent.pike 127.0.0.1 6379 1000 10   # 1000 clients'
Write-Host 'See README.md for the full runbook.'
