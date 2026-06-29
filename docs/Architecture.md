# Framework Architecture & Design

## 1. Why restful-booker as the framework development API

`https://restful-booker.herokuapp.com/` was chosen as the build-time sample
because it exercises **every capability** an enterprise framework must prove,
while staying free and public:

| Framework capability needed for the target application | What restful-booker provides |
|---|---|
| Authentication / token handling | `POST /auth` returns a token → demonstrates **correlation**. |
| Full CRUD business flow | `POST/GET/PUT/DELETE /booking` → realistic create→read→update→delete journey. |
| Dynamic, data-driven requests | JSON payloads with names, prices, dates → **CSV parameterization**. |
| Correlation between calls | `bookingid` from create reused in get/update/delete. |
| Positive & negative assertions | 200/201 success, 404-after-delete, 403-without-auth. |
| Header & content-type management | Requires `Content-Type`/`Accept: application/json`. |
| Auth on mutating calls | PUT/DELETE require Basic auth → models protected endpoints. |
| Health endpoint for smoke | `GET /ping` (201) → lightweight availability probe. |
| Stable & free for CI | Public, no licensing, safe to hammer at low/moderate load. |

Crucially, the structure mirrors a typical enterprise-style API tier (auth → resource
CRUD with protected mutations). Because **all endpoints, payloads, and load
knobs are externalised** (properties + CSV + `${__P()}`), migrating to the target application means
editing `config/*` and the request paths/payloads — **the framework skeleton,
correlation pattern, assertions, reporting, CI/CD, and RedLine13 packaging stay
identical.**

> Migration note: replace `base_url` and the per-sampler paths/bodies with the target application
> equivalents; if the target application uses bearer tokens, the `token` JSON extractor already
> demonstrates the correlation — swap the `Authorization` header value to
> `Bearer ${token}`.

---

## 2. Layered framework architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         PERFORMANCE FRAMEWORK                          │
├──────────────────────────────────────────────────────────────────────┤
│  CONFIGURATION LAYER                                                   │
│   config/user.properties        → JMeter engine + reporting tuning     │
│   config/environment.properties → active env (default)                 │
│   config/env/{dev,qa,uat,perf,prod}.properties → per-env overrides     │
│   All consumed via ${__P(name,default)} — zero hard-coding             │
├──────────────────────────────────────────────────────────────────────┤
│  TEST DATA LAYER                                                       │
│   data/testdata.csv  (CSV Data Set Config, share=all, recycle)         │
│   data/users.csv     (credentials pool)                                │
│   Dynamic payloads, unique rows, correlation (token, bookingid)        │
├──────────────────────────────────────────────────────────────────────┤
│  REUSABLE COMPONENT LAYER                                              │
│   HTTP Request Defaults · HTTP Header Manager · Cookie Manager         │
│   Test Fragment (TF - Business Modules) + Module Controllers           │
│   Transaction Controllers (TX_/MOD_) · Uniform Random Timer            │
├──────────────────────────────────────────────────────────────────────┤
│  VALIDATION LAYER                                                      │
│   Response Assertions (codes 200/201/404) · Duration (SLA) Assertions  │
│   JSONPath Assertions (token, bookingid) · Text & Negative assertions  │
├──────────────────────────────────────────────────────────────────────┤
│  EXECUTION LAYER (load profiles)                                       │
│   Smoke · EndToEnd · Load · Stress(4 steps) · Spike(3 grp) · Soak      │
│   Thread counts/ramp/duration all property-driven                      │
├──────────────────────────────────────────────────────────────────────┤
│  OBSERVABILITY LAYER                                                   │
│   HTML Dashboard (P90/P95/P99, TPS, error%, throughput, Apdex)         │
│   JTL (CSV) · Summary/Aggregate (on demand) · Debug Sampler            │
├──────────────────────────────────────────────────────────────────────┤
│  DELIVERY LAYER                                                        │
│   scripts/run-test.(ps1|sh) · CI/CD (Jenkins/Azure/GitHub)             │
│   RedLine13 distributed cloud execution (AWS generators)               │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 3. Scenario matrix

| Plan | Threads (default) | Pattern | Goal | Key property knobs |
|---|---|---|---|---|
| `SmokeTest.jmx` | 1 × 1 loop | single pass CRUD | health/availability | `smoke_users`, `smoke_loops` |
| `EndToEndFlow.jmx` | 1 × 1 loop | modular journey + verify update/deletion | functional correctness under tooling | `e2e_users`, `e2e_loops` |
| `LoadTest.jmx` | `users=50`, 600s | steady state | production-like load, throughput | `users`, `rampup`, `duration` |
| `StressTest.jmx` | 4 staged groups (50→100→200→400) | progressive climb | find breaking point | `stress_sN_users`, `stress_sN_delay`, `stress_sN_dur` |
| `SpikeTest.jmx` | baseline + 2 bursts | sudden surges | elasticity / recovery | `spike_baseline_users`, `spike1_users`, `spike2_users`, `*_delay`, `*_hold` |
| `SoakTest.jmx` | `soak_users=50`, 1800s | long steady | memory leaks / degradation | `soak_users`, `soak_duration` |

All six share the **identical business flow body** (authored once in
`SmokeTest.jmx`, propagated to the load profiles by `scripts/generate-plans.ps1`)
— only the Thread Group shape differs. This guarantees consistency: a fix to the
flow regenerates everywhere.

---

## 4. Endpoint reference (sample API)

| Step | Method | Path | Auth | Success | Extracted/Asserted |
|---|---|---|---|---|---|
| Health | GET | `/ping` | none | 201 | response code |
| Authenticate | POST | `/auth` | none | 200 | `$.token` |
| Create | POST | `/booking` | none | 200 | `$.bookingid` |
| Retrieve | GET | `/booking/{id}` | none | 200 | firstname present |
| Update | PUT | `/booking/{id}` | Basic | 200 | updated value present |
| Verify update | GET | `/booking/{id}` | none | 200 | `firstname-UPD` |
| Delete | DELETE | `/booking/{id}` | Basic | 201 | response code |
| Verify deletion | GET | `/booking/{id}` | none | 404 | negative assertion |
