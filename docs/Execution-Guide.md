# Execution Guide

Three execution tiers: **Local** (your machine), **RedLine13** (cloud, modest),
and **Production-Scale** (distributed, multi-region).

---

## A. Local Execution (start here — minimal load)

### Prerequisites
- Apache JMeter installed. Either add `<JMETER>/bin` to `PATH`, or set
  `JMETER_HOME` (e.g. `C:\apache-jmeter-5.6.3`).
- Java 17+ (`java -version`).

### Quickest smoke (GUI sanity check)
1. Open JMeter GUI → `File → Open` → `jmx/SmokeTest.jmx`.
2. Enable **View Results Tree** (currently disabled) temporarily.
3. Click **Start**. Confirm green results and passing assertions.
   > Never run Load/Stress/Spike/Soak in the GUI — GUI is for editing/debug only.

### Non-GUI run (the real way) — Windows
```powershell
# From PerformanceFramework/
.\scripts\run-test.ps1 -Plan SmokeTest -Env qa
.\scripts\run-test.ps1 -Plan EndToEndFlow -Env qa
# Small local load with overrides:
.\scripts\run-test.ps1 -Plan LoadTest -Env qa -Props @{users=20; rampup=30; duration=120}
```

### Non-GUI run — Linux/macOS/CI
```bash
chmod +x scripts/run-test.sh
./scripts/run-test.sh SmokeTest qa
./scripts/run-test.sh LoadTest qa -Jusers=20 -Jrampup=30 -Jduration=120
```

### Raw JMeter command (what the scripts wrap)
```bash
jmeter -n -t jmx/SmokeTest.jmx \
  -q config/env/qa.properties \
  -p config/user.properties \
  -l results/smoke.jtl -j results/jmeter.log \
  -e -o reports/smoke \
  -Jtestdata_file=data/testdata.csv
```

### Outputs
- `results/<run-id>/results.jtl` — raw samples (CSV).
- `reports/<run-id>/index.html` — **JMeter HTML dashboard** (open in browser).
- `results/<run-id>/jmeter.log` — engine log.

> **Do not** attempt 5k/50k threads locally. One laptop ≈ a few hundred light
> threads before the generator itself becomes the bottleneck. Scale on RedLine13.

---

## B. RedLine13 Execution (cloud, no edits required)

1. **Validate locally first** (Section A) — only upload green plans.
2. **RedLine13 → New Test → JMeter Test.**
3. **Attach files:**
   - Plan: `jmx/LoadTest.jmx` (or any plan).
   - Additional file: `data/testdata.csv`.
4. **JMeter Properties box** — paste your environment + load profile, e.g.:
   ```
   base_url=its-perf.internal.company.com
   protocol=https
   port=443
   users=500
   rampup=180
   duration=900
   think_time_min=1000
   think_time_range=3000
   testdata_file=testdata.csv
   ```
5. **Generators:** instance type + count + region (start: 1 × `c5.large`).
6. **Start** and watch live RPS / response time / error% / active threads.
7. **Download** the JTL when done; regenerate the HTML dashboard locally:
   ```bash
   jmeter -g results/redline13-results.jtl -o reports/redline13-run
   ```

> Because the JMX uses filename-only data references and `${__P()}` everywhere,
> no field needs editing after upload — change behaviour via the Properties box.

---

## C. Production-Scale Execution (distributed, multi-region)

For 5k → 50k VUs. Treat as a coordinated event, not an ad-hoc run.

### Pre-flight checklist
- [ ] AWS configured per `docs/AWS-Setup.md` (IAM key, EC2 quota, SGs).
- [ ] SUT allows generator IP ranges (network/firewall change approved).
- [ ] Change window / sign-off obtained (especially anything touching PROD).
- [ ] Test data volume sufficient (unique users/bookings) — expand
      `data/testdata.csv` so threads don't collide unrealistically.
- [ ] Monitoring ready on the SUT side (APM, infra metrics, DB, logs).
- [ ] Baseline captured (a Smoke/Load run for comparison).

### Run
1. Configure multiple **generator groups**, one per region, with `users` split
   by the traffic-share table (`RedLine13-Guide.md` §4).
2. Match instance type/count to the scaling table (`RedLine13-Guide.md` §5).
3. **Stagger ramp:** set `rampup` to ≥ 300–600s for 10k+ so you observe
   degradation curves, not a thundering herd.
4. Start; monitor **both** RedLine13 (client-side) and SUT APM (server-side).
   Correlate response-time inflection with server CPU/DB/queue saturation.
5. For **Stress**, let the staged thread groups climb until error% spikes —
   that inflection is the breaking point. For **Soak**, hold steady for hours
   and watch for slow memory growth / GC pressure / connection-pool exhaustion.

### After
- Confirm **all generators terminated** in EC2 (cost hygiene).
- Archive JTL + HTML dashboard with the run metadata (date, build, profile).
- Compare P95/P99, throughput, and error% against the baseline and SLAs.
