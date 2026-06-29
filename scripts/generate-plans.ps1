# =====================================================================
# generate-plans.ps1
# Derives the load-profile JMX plans (Load/Stress/Spike/Soak) from the
# validated business flow inside SmokeTest.jmx. The business flow (the
# six CRUD transaction controllers + timer + correlation + assertions)
# is authored ONCE in SmokeTest.jmx and reused here by swapping only the
# Thread Group(s). This keeps every plan consistent and RedLine13-safe.
#
# Re-run this whenever the business flow changes:
#   pwsh ./scripts/generate-plans.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'
$jmxDir = Join-Path $PSScriptRoot '..\jmx'
$src    = Join-Path $jmxDir 'SmokeTest.jmx'

# ---- Thread Group definitions (standard ThreadGroup only) -----------
$tgLoad = @'
<ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="TG - Load (steady state)" enabled="true">
  <stringProp name="ThreadGroup.on_sample_error">continue</stringProp>
  <elementProp name="ThreadGroup.main_controller" elementType="LoopController" guiclass="LoopControlPanel" testclass="LoopController" testname="Loop Controller" enabled="true">
    <boolProp name="LoopController.continue_forever">true</boolProp>
    <stringProp name="LoopController.loops">-1</stringProp>
  </elementProp>
  <stringProp name="ThreadGroup.num_threads">${__P(users,50)}</stringProp>
  <stringProp name="ThreadGroup.ramp_time">${__P(rampup,60)}</stringProp>
  <boolProp name="ThreadGroup.scheduler">true</boolProp>
  <stringProp name="ThreadGroup.duration">${__P(duration,600)}</stringProp>
  <stringProp name="ThreadGroup.delay">${__P(startup_delay,0)}</stringProp>
</ThreadGroup>
'@

function StressStep($name,$users,$ramp,$delay,$dur) { @"
<ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="$name" enabled="true">
  <stringProp name="ThreadGroup.on_sample_error">continue</stringProp>
  <elementProp name="ThreadGroup.main_controller" elementType="LoopController" guiclass="LoopControlPanel" testclass="LoopController" testname="Loop Controller" enabled="true">
    <boolProp name="LoopController.continue_forever">true</boolProp>
    <stringProp name="LoopController.loops">-1</stringProp>
  </elementProp>
  <stringProp name="ThreadGroup.num_threads">$users</stringProp>
  <stringProp name="ThreadGroup.ramp_time">$ramp</stringProp>
  <boolProp name="ThreadGroup.scheduler">true</boolProp>
  <stringProp name="ThreadGroup.duration">$dur</stringProp>
  <stringProp name="ThreadGroup.delay">$delay</stringProp>
</ThreadGroup>
"@ }

# Progressive stress: concurrency climbs in steps until breaking point.
$tgStress = @(
  (StressStep 'TG - Stress Step 1' '${__P(stress_s1_users,50)}'  '${__P(stress_s1_ramp,60)}'  '0'   '${__P(stress_s1_dur,900)}'),
  (StressStep 'TG - Stress Step 2' '${__P(stress_s2_users,100)}' '${__P(stress_s2_ramp,60)}'  '${__P(stress_s2_delay,180)}' '${__P(stress_s2_dur,720)}'),
  (StressStep 'TG - Stress Step 3' '${__P(stress_s3_users,200)}' '${__P(stress_s3_ramp,90)}'  '${__P(stress_s3_delay,360)}' '${__P(stress_s3_dur,540)}'),
  (StressStep 'TG - Stress Step 4' '${__P(stress_s4_users,400)}' '${__P(stress_s4_ramp,120)}' '${__P(stress_s4_delay,540)}' '${__P(stress_s4_dur,360)}')
)

# Spike: steady baseline + sudden bursts. Local-safe defaults; scale on
# RedLine13 to baseline=100, spike1=1000, spike2=5000 via -J overrides.
$tgSpike = @(
  (StressStep 'TG - Spike Baseline'   '${__P(spike_baseline_users,20)}' '${__P(spike_baseline_ramp,30)}' '0'   '${__P(spike_duration,600)}'),
  (StressStep 'TG - Spike Burst 1'    '${__P(spike1_users,100)}'        '${__P(spike1_ramp,10)}'        '${__P(spike1_delay,120)}' '${__P(spike1_hold,60)}'),
  (StressStep 'TG - Spike Burst 2'    '${__P(spike2_users,200)}'        '${__P(spike2_ramp,15)}'        '${__P(spike2_delay,300)}' '${__P(spike2_hold,60)}')
)

$tgSoak = @(
  (StressStep 'TG - Soak (endurance)' '${__P(soak_users,50)}' '${__P(soak_rampup,120)}' '0' '${__P(soak_duration,1800)}')
)

$plans = @{
  'LoadTest.jmx'   = @{ name='API - Load Test';      tgs=@($tgLoad) }
  'StressTest.jmx' = @{ name='API - Stress Test';    tgs=$tgStress }
  'SpikeTest.jmx'  = @{ name='API - Spike Test';     tgs=$tgSpike }
  'SoakTest.jmx'   = @{ name='API - Soak Test';      tgs=$tgSoak }
}

foreach ($file in $plans.Keys) {
  [xml]$doc = Get-Content $src -Raw
  $inner = $doc.SelectSingleNode('/jmeterTestPlan/hashTree/hashTree')
  $tg    = $inner.SelectSingleNode('ThreadGroup')
  $body  = $tg.NextSibling                       # the body hashTree
  $bodyXml = $body.OuterXml

  [void]$inner.RemoveChild($tg)
  [void]$inner.RemoveChild($body)

  foreach ($tgXml in $plans[$file].tgs) {
    $fragTg = $doc.CreateDocumentFragment(); $fragTg.InnerXml = $tgXml
    [void]$inner.AppendChild($fragTg)
    $fragBody = $doc.CreateDocumentFragment(); $fragBody.InnerXml = $bodyXml
    [void]$inner.AppendChild($fragBody)
  }

  $doc.SelectSingleNode('/jmeterTestPlan/hashTree/TestPlan').SetAttribute('testname', $plans[$file].name)
  $out = Join-Path $jmxDir $file
  $doc.Save($out)
  Write-Host "Generated $file"
}
Write-Host "Done."
