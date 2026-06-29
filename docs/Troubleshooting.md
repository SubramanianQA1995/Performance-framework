# Troubleshooting & Debugging Guide

## Debugging features built into the framework

- **Debug Sampler** (`DBG - Variables Snapshot`) — in Smoke & E2E plans. Shows
  all JMeter variables (token, bookingid, CSV row values) per iteration. Pair
  with a temporary **View Results Tree** to inspect them.
- **Log-friendly naming** — samplers/transactions are prefixed (`TX_0n_*`,
  `MOD_*`) so they sort and read clearly in the HTML dashboard and JTL.
- **Default values on extractors** — `TOKEN_NOT_FOUND` / `BOOKINGID_NOT_FOUND`
  make correlation failures obvious instead of silently blank.
- **Custom assertion messages** — e.g. health check and verify-deletion explain
  *why* they failed.

### Turn on verbose debugging locally
1. Open the plan in JMeter GUI.
2. Enable **View Results Tree** (set to "Errors" or all).
3. Run a single user/iteration (`smoke_users=1`).
4. Inspect request/response + the Debug Sampler output.
5. **Disable** View Results Tree again before any real load run.

---

## Common issues

| Symptom | Likely cause | Fix |
|---|---|---|
| `jmeter` not recognised | Not on PATH | Add `<JMETER>/bin` to PATH or set `JMETER_HOME`; scripts honour `JMETER_HOME`. |
| All requests fail, `Unknown host` | `base_url` wrong / no network | Check `config/env/<env>.properties`; verify DNS/VPN to SUT. |
| 401/403 on PUT/DELETE | Auth header missing/wrong | Plans send `Authorization: Basic ${__P(auth_basic,...)}` on every request (concurrency-safe). Confirm `auth_basic` = base64("user:pass"). Regenerate: `[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("admin:password123"))`. Do NOT rely on the HTTP Authorization Manager — its preemptive Basic auth is unreliable across concurrent threads. |
| `token = TOKEN_NOT_FOUND` | `/auth` failed or schema changed | Check the auth response JSON; confirm `$.token` path; check credentials. |
| `bookingid = BOOKINGID_NOT_FOUND` | Create failed / response shape changed | Verify POST `/booking` returns `{ "bookingid": N }`; check `Content-Type: application/json`. |
| `CSV file not found` | Data file not beside plan | Run via the scripts (they pass `-Jtestdata_file=...`), or upload `testdata.csv` next to the JMX on RedLine13. |
| High error% only at scale | Generator saturation, not SUT | Check generator CPU; reduce threads/generator, add generators (see scaling table). |
| `OutOfMemoryError` in jmeter.log | Heap too small / response logging on | Raise heap (`HEAP="-Xms1g -Xmx4g"` env), keep response data off (already configured), reduce threads. |
| Response times look artificially high | Think-time counted? Timer is excluded from samples (Transaction Controllers have `includeTimers=false`) | Verify, and check actual SUT/server metrics. |
| Dashboard empty / "no samples" | JTL empty or wrong format | Ensure CSV output format (set in `user.properties`); confirm the run actually produced samples. |
| `Address already in use` at high load | Ephemeral port exhaustion on generator | Enable keep-alive (already on), tune OS ephemeral port range / `TIME_WAIT`, add generators. |

---

## JTL → HTML dashboard (post-process any results)
```bash
jmeter -g results/<run-id>/results.jtl -o reports/<run-id>
```

## Increasing JMeter heap (large local runs)
```bash
# Linux/macOS
export HEAP="-Xms1g -Xmx4g -XX:MaxMetaspaceSize=256m"
# Windows PowerShell
$env:HEAP="-Xms1g -Xmx4g -XX:MaxMetaspaceSize=256m"
```

## Sanity-check a plan without load
```bash
jmeter -n -t jmx/SmokeTest.jmx -Jsmoke_users=1 -Jsmoke_loops=1 \
  -q config/env/qa.properties -l results/sanity.jtl -j results/sanity.log
```
