# ITS — Enterprise Load & Performance Testing Framework

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Apache JMeter](https://img.shields.io/badge/Apache%20JMeter-5.6.3-D22128?logo=apachejmeter&logoColor=white)
![Java](https://img.shields.io/badge/Java-17%2B-007396?logo=openjdk&logoColor=white)
![No Plugins](https://img.shields.io/badge/plugins-none-success)
![CI](https://github.com/SubramanianQA1995/its-performance-framework/actions/workflows/perf-tests.yml/badge.svg)

A reusable, enterprise-grade Apache JMeter framework for the **ITS** platform
modernization program. Built on the public **restful-booker** API for
development, and designed so the sample API can be swapped for ITS application
APIs/UI flows with **minimal change**. Distributed cloud execution via
**RedLine13** on **AWS**, with **Jenkins / Azure DevOps / GitHub Actions** CI/CD.

> **No third-party JMeter plugins. No Plugin Manager. No custom Java. No external
> JARs.** Standard JMeter components only — so every `.jmx` opens, runs, and
> uploads to RedLine13 with zero modification.

---

## Table of Contents
1. [Framework Overview](#1-framework-overview)
2. [Folder Structure](#2-folder-structure)
3. [Installation](#3-installation)
4. [Execution](#4-execution)
5. [Test Scenarios](#5-test-scenarios)
6. [Configuration](#6-configuration)
7. [Reporting](#7-reporting)
8. [RedLine13 Deployment](#8-redline13-deployment)
9. [AWS Setup](#9-aws-setup)
10. [CI/CD Setup](#10-cicd-setup)
11. [Troubleshooting](#11-troubleshooting)
12. [Migrating from restful-booker to ITS](#12-migrating-from-restful-booker-to-its)

---

## 1. Framework Overview

- **Sample API:** `https://restful-booker.herokuapp.com/` — exercises auth,
  full CRUD, correlation, protected mutations, and a health probe. See
  [`docs/Architecture.md`](docs/Architecture.md) for the full justification.
- **Six load profiles:** Smoke, End-to-End, Load, Stress, Spike, Soak.
- **Single source of truth for the business flow:** authored once in
  `SmokeTest.jmx`, propagated to the load profiles by
  `scripts/generate-plans.ps1` — only the Thread Group shape differs.
- **Everything externalised:** environment + load profile live in
  `config/`; test data in `data/`; all referenced via `${__P(name,default)}`.
- **Layered design:** Config → Test Data → Reusable Components → Validation →
  Execution → Observability → Delivery (diagram in `docs/Architecture.md`).

---

## 2. Folder Structure

```
PerformanceFramework/
├── config/
│   ├── user.properties              # JMeter engine + HTML dashboard tuning
│   ├── environment.properties       # active/default environment
│   └── env/
│       ├── dev.properties
│       ├── qa.properties
│       ├── uat.properties
│       ├── perf.properties
│       └── prod.properties          # optional, read-only smoke by default
├── data/
│   ├── testdata.csv                 # booking test data (CSV Data Set Config)
│   └── users.csv                    # credentials pool
├── jmx/
│   ├── SmokeTest.jmx                # source of the shared business flow
│   ├── EndToEndFlow.jmx             # Test Fragment + Module Controllers
│   ├── LoadTest.jmx                 # generated
│   ├── StressTest.jmx               # generated (4 staged groups)
│   ├── SpikeTest.jmx                # generated (baseline + 2 bursts)
│   └── SoakTest.jmx                 # generated (long steady)
├── scripts/
│   ├── run-test.ps1                 # Windows runner (+ HTML dashboard)
│   ├── run-test.sh                  # Linux/macOS/CI runner
│   └── generate-plans.ps1           # regenerates load profiles from Smoke body
├── ci-cd/
│   ├── Jenkinsfile
│   ├── azure-pipelines.yml
│   └── github-actions-perf.yml
├── docs/
│   ├── Architecture.md
│   ├── RedLine13-Guide.md
│   ├── AWS-Setup.md
│   ├── Execution-Guide.md
│   └── Troubleshooting.md
├── reports/                         # generated HTML dashboards (per run)
├── results/                         # generated JTL + logs (per run)
├── lib/                             # (empty — no external JARs by design)
└── README.md
```

---

## 3. Installation

1. **Java 17+** — `java -version`.
2. **Apache JMeter (latest)** — already installed per your setup. Either:
   - add `<JMETER>/bin` to your `PATH`, **or**
   - set `JMETER_HOME` (e.g. `C:\apache-jmeter-5.6.3`). The runner scripts use it.
3. Clone/copy this `PerformanceFramework/` folder.
4. Validate a plan is well-formed (optional):
   ```powershell
   [xml](Get-Content jmx/SmokeTest.jmx -Raw) | Out-Null; "OK"
   ```

No plugins or JARs to install — that is intentional.

---

## 4. Execution

**Windows (PowerShell):**
```powershell
.\scripts\run-test.ps1 -Plan SmokeTest -Env qa
.\scripts\run-test.ps1 -Plan LoadTest  -Env qa -Props @{users=20; rampup=30; duration=120}
```

**Linux/macOS/CI:**
```bash
chmod +x scripts/run-test.sh
./scripts/run-test.sh SmokeTest qa
./scripts/run-test.sh LoadTest  qa -Jusers=20 -Jrampup=30 -Jduration=120
```

**Raw JMeter:**
```bash
jmeter -n -t jmx/SmokeTest.jmx -q config/env/qa.properties -p config/user.properties \
       -l results/smoke.jtl -j results/jmeter.log -e -o reports/smoke \
       -Jtestdata_file=data/testdata.csv
```

> GUI mode is for **editing/debugging only**. Always drive load in non-GUI mode.
> Full tiered instructions: [`docs/Execution-Guide.md`](docs/Execution-Guide.md).

---

## 5. Test Scenarios

| Plan | Purpose | Default profile |
|---|---|---|
| **SmokeTest** | App health: ping → auth → create → get → update → delete | 1 user, 1 loop |
| **EndToEndFlow** | Realistic journey + verify-update + verify-deletion (modular) | 1 user, 1 loop |
| **LoadTest** | Production-like steady-state load & throughput | 50 users, 600s |
| **StressTest** | Progressive climb to find breaking point | 50→100→200→400 staged |
| **SpikeTest** | Sudden traffic bursts & recovery | baseline + 1000 + 5000* bursts |
| **SoakTest** | Endurance — memory leaks / degradation | 50 users, 30 min (extend to hours) |

\* Spike defaults are local-safe (20/100/200); scale to 100/1000/5000 via
RedLine13 properties. See [`docs/Architecture.md`](docs/Architecture.md) §3 for
the full scenario matrix and knobs.

---

## 6. Configuration

All behaviour is property-driven. Precedence (highest wins):

```
-J<key>=<val> on CLI / RedLine13 props  >  config/env/<env>.properties (-q)  >
config/environment.properties  >  ${__P(key, DEFAULT)} default in the JMX
```

Key properties: `base_url`, `protocol`, `port`, `auth_user`, `auth_password`,
`users`, `rampup`, `duration`, `think_time_min`, `think_time_range`,
`testdata_file`, and the `sla_*_ms` assertion thresholds. Switch environments
with `-Env dev|qa|uat|perf|prod`.

---

## 7. Reporting

Every run emits a **JMeter HTML Dashboard** (`reports/<run-id>/index.html`) with:

- **Throughput / Transactions Per Second (TPS)**
- **Error %**
- **Average response time**, plus **P90 / P95 / P99** (configured in
  `config/user.properties`)
- **Apdex** (satisfied 500ms / tolerated 1500ms — tune to ITS SLAs)
- Per-transaction tables (`TX_*` / `MOD_*`) and over-time graphs

Regenerate a dashboard from any JTL:
```bash
jmeter -g results/<run-id>/results.jtl -o reports/<run-id>
```
**Summary Report** and **Aggregate Report** listeners are embedded (disabled by
default to keep load runs light) — enable in the GUI for ad-hoc analysis.

---

## 8. RedLine13 Deployment

The plans are RedLine13-ready by construction (filename-only data refs,
property-driven, standard components, reliable Basic auth). Workflow:
**build → validate locally → package (JMX + `testdata.csv`) → upload →
configure generators/regions → set JMeter Properties → execute → download
JTL/HTML.** Full architecture diagrams, multi-region strategy, and the
100→50,000 VU scaling table are in
[`docs/RedLine13-Guide.md`](docs/RedLine13-Guide.md).

---

## 9. AWS Setup

RedLine13 launches generator EC2 instances in **your** AWS account. You'll need
an IAM user with scoped EC2 permissions, sufficient vCPU quota, and security-
group access from generators to the SUT. Least-privilege policy, EC2 sizing, SG
rules, and cost estimates: [`docs/AWS-Setup.md`](docs/AWS-Setup.md). *(Local
execution needs no AWS.)*

---

## 10. CI/CD Setup

Ready-to-use pipelines in `ci-cd/`, all following **Smoke (gate) → Load profile
→ Report → Publish artifacts**:

- **Jenkins** — `ci-cd/Jenkinsfile` (declarative; HTML publish + perf trend).
- **Azure DevOps** — `ci-cd/azure-pipelines.yml` (installs JMeter, publishes
  JTL + dashboard artifacts).
- **GitHub Actions** — `ci-cd/github-actions-perf.yml` (place at
  `.github/workflows/perf-tests.yml`; manual dispatch + scheduled smoke).

Each is parameterized by environment, test type, users, ramp-up, and duration.

---

## 11. Troubleshooting

Built-in aids: **Debug Sampler**, log-friendly `TX_/MOD_` naming, extractor
default values (`TOKEN_NOT_FOUND` / `BOOKINGID_NOT_FOUND`), and custom assertion
messages. Common issues, fixes, heap tuning, and the JTL→HTML command are in
[`docs/Troubleshooting.md`](docs/Troubleshooting.md).

---

## 12. Migrating from restful-booker to ITS

The framework skeleton is intended to outlive the sample API. To target ITS:

1. **Endpoints/host** — set `base_url`, `protocol`, `port` in `config/env/*`.
2. **Paths & payloads** — update the sampler paths and JSON bodies to ITS APIs
   (keep the Transaction/Module structure).
3. **Auth** — the `token` JSON extractor already demonstrates correlation. If
   ITS uses bearer tokens, change the `Authorization` header to `Bearer
   ${token}`; if it uses Basic, it already works.
4. **Test data** — replace `data/testdata.csv` columns with ITS data; expand
   rows for unique-user realism at scale.
5. **Assertions/SLAs** — adjust `sla_*_ms` and response/JSON assertions to ITS
   contracts.
6. **UI flows (optional)** — for browser-level journeys, add HTTP samplers for
   the web tier following the same patterns; everything else (config, reporting,
   CI/CD, RedLine13 packaging) is unchanged.

Because all of the above is data/config — not structural — the **reusable
components, correlation pattern, reporting, CI/CD, and RedLine13 deployment stay
identical** between the current platform and the modernized ITS platform.
