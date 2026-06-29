# RedLine13 Deployment & Distributed Load Guide

This guide explains how the JMX plans in `jmx/` are executed at scale on
**RedLine13** using AWS-based load generators, with **zero modification**
after upload.

---

## 1. Why these JMX files are RedLine13-ready

RedLine13 runs stock Apache JMeter on each load generator and feeds it your
`.jmx` plus any data files. The framework was deliberately built to satisfy
RedLine13's constraints:

| Requirement | How the framework complies |
|---|---|
| No custom plugins | Only standard JMeter components used (Transaction/Module Controllers, JSON Extractor, Response/Duration/JSONPath Assertions, Uniform Random Timer, CSV Data Set). |
| No external JARs | No BeanShell/Groovy custom classes, no Plugin Manager components. |
| Portable data file references | `CSV Data Set Config` uses **filename only** (`testdata.csv`), not absolute paths. Upload the CSV alongside the JMX. |
| Externalised load profile | Every load knob is a `${__P(name,default)}` property, set in the RedLine13 *JMeter Properties* box — no GUI editing needed. |
| Reliable auth | Every request carries `Authorization: Basic ${__P(auth_basic,...)}` — a precomputed base64 property sent explicitly (no plugin, no function, concurrency-safe), verified under concurrent load against the live API. |

---

## 2. RedLine13 Architecture

```
                          ┌──────────────────────────────┐
                          │        RedLine13 SaaS         │
                          │      Controller / Console      │
                          │  (test config, orchestration,  │
                          │   live charts, aggregated DB)  │
                          └───────────────┬────────────────┘
                                          │  AWS API (your IAM keys)
                 ┌────────────────────────┼────────────────────────┐
                 │ launches EC2            │                        │
                 ▼                         ▼                        ▼
        ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
        │ Load Generator  │      │ Load Generator  │      │ Load Generator  │
        │   (EC2 + Agent) │      │   (EC2 + Agent) │      │   (EC2 + Agent) │
        │  us-east-1      │      │  us-west-2      │      │  eu-west-1      │
        │  JMeter engine  │      │  JMeter engine  │      │  JMeter engine  │
        │  N threads      │      │  N threads      │      │  N threads      │
        └────────┬────────┘      └────────┬────────┘      └────────┬────────┘
                 │ HTTPS load             │                        │
                 └────────────────────────┼────────────────────────┘
                                          ▼
                          ┌──────────────────────────────┐
                          │   System Under Test (SUT)     │
                          │  ITS: UI / API / Services      │
                          └──────────────────────────────┘
```

### Components explained

- **Controller (RedLine13 Console):** the SaaS web app. You define the test,
  attach the JMX + data files, choose generators/regions, set JMeter
  properties, start/stop the run, and view live + historical reports. It does
  **not** generate load itself.
- **Load Generators:** EC2 instances RedLine13 launches in **your** AWS account.
  Each runs the **RedLine13 Agent** + a full **JMeter engine** executing your
  plan with a slice of the total threads.
- **Agent:** lightweight process on each generator that pulls the test package,
  starts JMeter, streams metrics back to the controller, and tears down.
- **Regions:** you pick AWS regions per generator to model geographically
  distributed users (latency realism + true distributed throughput).
- **Distributed load generation:** total VUs = (threads per generator) ×
  (number of generators). The controller aggregates all generators' results
  into one report.

---

## 3. JMeter + RedLine13 Workflow

```
 1. BUILD            2. VALIDATE          3. PACKAGE
 ┌──────────┐        ┌──────────┐         ┌──────────────┐
 │ Author/  │        │ Run Smoke│         │ JMX + CSV    │
 │ edit JMX │  ───▶  │ locally  │  ───▶   │ (+ props)    │
 │ in JMeter│        │ -n -t ...│         │ filename-only│
 └──────────┘        └──────────┘         └──────────────┘
        │                                         │
        ▼                                         ▼
 4. UPLOAD           5. CONFIGURE         6. EXECUTE          7. REPORT
 ┌──────────┐        ┌──────────────┐     ┌──────────┐        ┌──────────┐
 │ New Test │  ───▶  │ generators,  │ ──▶ │ Start &  │  ───▶  │ Live +   │
 │ → JMeter │        │ regions,     │     │ monitor  │        │ download │
 │ test     │        │ JMeter props │     │ live     │        │ JTL/HTML │
 └──────────┘        └──────────────┘     └──────────┘        └──────────┘
```

**Step-by-step:**

1. **Build script locally** — author/adjust in JMeter GUI (or reuse as-is).
2. **Validate locally** — `scripts/run-test.ps1 -Plan SmokeTest -Env qa`
   (or `.sh`). Confirm 0 errors and assertions pass.
3. **Package files** — gather the chosen `*.jmx` and `data/testdata.csv`.
   Filenames only; no folders required by the JMX.
4. **Upload to RedLine13** — *New Test → JMeter Test*; attach the JMX as the
   plan and the CSV as an additional file.
5. **Configure cloud generators** — choose instance type, number of
   generators, region(s), and threads/generator. Paste load properties into
   the *JMeter Properties* box (see below).
6. **Execute test** — start; watch live RPS, response time, errors, active VUs.
7. **Collect reports** — download the aggregated JTL/CSV and generate the
   JMeter HTML dashboard locally if you want the full percentile breakdown.

### JMeter Properties to paste in RedLine13 (example: 1000 VUs Load)

```
base_url=its-perf.internal.company.com
protocol=https
port=443
auth_user=admin
auth_password=password123
users=1000
rampup=300
duration=1800
think_time_min=1000
think_time_range=3000
testdata_file=testdata.csv
```

> `users` here is **per generator**. With 10 generators × 100 threads you also
> reach 1000 VUs — prefer more generators with fewer threads each for realism
> and to avoid generator CPU saturation.

---

## 4. Multi-Region Load Testing

Model a global customer base by spreading generators across regions. In
RedLine13, add multiple generator groups, each pinned to a region:

```
                         ITS SUT (single endpoint or GSLB)
                                     ▲
        ┌───────────────┬────────────┼────────────┬───────────────┐
        │               │            │            │               │
   us-east-1       us-west-2     eu-west-1    eu-central-1   ap-southeast-1
   (US East)       (US West)    (Europe-UK)  (Europe-DE)      (APAC-SG)
   40% of VUs      15% of VUs    25% of VUs    10% of VUs      10% of VUs
```

| Geography | AWS region | Suggested traffic share |
|---|---|---|
| US East   | `us-east-1`      | 40% |
| US West   | `us-west-2`      | 15% |
| Europe    | `eu-west-1` / `eu-central-1` | 35% |
| APAC      | `ap-southeast-1` / `ap-south-1` | 10% |

Distribute the share by setting `users` per generator group proportionally.
Tag each run so regional latency differences are visible in the report.

---

## 5. Scaling Strategy

Per-generator thread guidance assumes a lightweight REST workload (this API).
Always cap generator CPU < ~75%; if higher, add generators, don't add threads.

| Target VUs | EC2 instance (per gen) | Generators | Threads / gen | Notes |
|-----------:|------------------------|-----------:|--------------:|-------|
| 100        | `t3.medium`            | 1          | 100           | Smoke/Load lab; single region. |
| 1,000      | `c5.large` (2 vCPU)    | 2          | 500           | Or 4 × 250 for headroom. |
| 5,000      | `c5.xlarge` (4 vCPU)   | 5          | 1,000         | Multi-region recommended. |
| 10,000     | `c5.xlarge`            | 10         | 1,000         | 2–3 regions; stagger ramp. |
| 50,000     | `c5.2xlarge` (8 vCPU)  | 25         | 2,000         | 4 regions; pre-warm SUT & ELB; coordinate change window. |

**Rules of thumb**
- ~500–2,000 threads per modern vCPU-rich generator for light REST; far fewer
  if responses are large or you enable full response logging.
- Disable `View Results Tree` / full response capture at scale (already
  disabled in these plans).
- Ramp 50k over **≥ 5–10 minutes**; never instantly, or you test the load
  balancer's cold start, not the app.
- Keep one generator per ~2,000 VUs as a safety ceiling for this workload.

See `docs/AWS-Setup.md` for the IAM keys and EC2 limits RedLine13 needs to
launch these generators in your account.
