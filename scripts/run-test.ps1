# =====================================================================
# run-test.ps1  (Windows / PowerShell)
# Non-GUI JMeter runner with HTML dashboard generation.
#
# Usage:
#   .\scripts\run-test.ps1 -Plan SmokeTest -Env qa
#   .\scripts\run-test.ps1 -Plan LoadTest  -Env perf -Props @{users=200;rampup=120;duration=900}
#
# Requires: jmeter on PATH (or set $env:JMETER_HOME).
# =====================================================================
param(
  [Parameter(Mandatory=$true)][string]$Plan,         # SmokeTest | EndToEndFlow | LoadTest | StressTest | SpikeTest | SoakTest
  [string]$Env = "qa",                               # dev | qa | uat | perf | prod
  [hashtable]$Props = @{}                            # ad-hoc -J overrides
)
$ErrorActionPreference = "Stop"
$root      = Resolve-Path (Join-Path $PSScriptRoot "..")
$stamp     = Get-Date -Format "yyyyMMdd-HHmmss"
$runId     = "$Plan-$Env-$stamp"
$jmx       = Join-Path $root "jmx\$Plan.jmx"
$envFile   = Join-Path $root "config\env\$Env.properties"
$userProps = Join-Path $root "config\user.properties"
$resultDir = Join-Path $root "results\$runId"
$reportDir = Join-Path $root "reports\$runId"
$jtl       = Join-Path $resultDir "results.jtl"
$logFile   = Join-Path $resultDir "jmeter.log"

if (-not (Test-Path $jmx))     { throw "Plan not found: $jmx" }
if (-not (Test-Path $envFile)) { throw "Env file not found: $envFile" }
New-Item -ItemType Directory -Force -Path $resultDir | Out-Null

# Resolve jmeter executable
$jmeter = if ($env:JMETER_HOME) { Join-Path $env:JMETER_HOME "bin\jmeter.bat" } else { "jmeter" }

# Build -J overrides (env file is loaded via -q so its keys become properties)
$argList = @(
  "-n",
  "-t", $jmx,
  "-q", $envFile,
  "-p", $userProps,
  "-l", $jtl,
  "-j", $logFile,
  "-e", "-o", $reportDir
)
# data dir so testdata.csv resolves by filename
$argList += @("-Jtestdata_file=$(Join-Path $root 'data\testdata.csv')")
foreach ($k in $Props.Keys) { $argList += "-J$k=$($Props[$k])" }

Write-Host "=== Performance Run: $runId ===" -ForegroundColor Cyan
Write-Host "Plan   : $jmx"
Write-Host "Env    : $envFile"
Write-Host "Results: $jtl"
Write-Host "Report : $reportDir"
Write-Host "Cmd    : $jmeter $($argList -join ' ')"

# JMeter on modern JDKs prints deprecation WARNINGs to stderr. Under
# $ErrorActionPreference='Stop', PowerShell would promote those stderr lines to
# terminating errors even though JMeter exits 0. Convert stderr to strings and
# trust the real process exit code instead.
$ErrorActionPreference = 'Continue'
& $jmeter @argList 2>&1 | ForEach-Object { Write-Host $_ }
$jmeterExit = $LASTEXITCODE
if ($jmeterExit -ne 0) { throw "JMeter exited with code $jmeterExit" }
Write-Host "`nHTML dashboard: $reportDir\index.html" -ForegroundColor Green
