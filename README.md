# asset-tests — Daml Script unit tests with `dpm trace test`

A small, self-contained Daml package that shows how to run **Daml Script unit
tests** through `dpm trace test` and wire it into CI/CD.

`daml test` runs your Script tests but only prints a coverage summary; the
transaction trees go to per-script HTML files meant for the IDE, and a failing
test gives you a verbose message with no rendered source. `dpm trace test` runs
the same tests and, in the terminal and as JSON:

- renders each script's **transaction tree** (creates, exercises, archives,
  `submitMustFail` guard nodes, parties, arguments, source locations);
- maps every **failed test back to source** — the test call site *and* the
  contract invariant (`assertMsg`/`abort`/`ensure`) that rejected it;
- returns a **non-zero exit code** when any test fails, so it gates CI;
- emits a machine-readable report with `--print-json` and standard JUnit XML
  with `--junit`.

No Canton node is involved: `daml test` uses the in-memory IDE ledger, so this
runs anywhere a Daml toolchain runs.

## Layout

```
daml/Asset.daml   # an IOU-style Asset contract: Transfer, Split, Burn, ensure quantity > 0
daml/Test.daml    # Daml Script unit tests: happy paths + submitMustFail guards (the gate)
daml/FailureDemo.daml      # one deliberately failing test, to show source-mapped failures
itests/           # integration tests (lit) that run against a real local Canton
.github/workflows/ci.yml          # unit-test CI gate (dpm trace test)
.github/workflows/integration.yml # integration CI (managed Canton + lit)
run-demo.sh       # green run -> inject a regression -> red run -> revert
```

The tests mix the cases a real suite has:

| Test | What it exercises |
| --- | --- |
| `testIssue` | create, payload/observer visibility |
| `testTransfer` | consuming exercise → archive + child create |
| `testSplit` | exercise → two child creates |
| `testCannotIssueZero` | `ensure quantity > 0` rejection (`submitMustFail`) |
| `testStrangerCannotTransfer` | authorization rejection (`submitMustFail`) |
| `testBadSplitFails` | in-choice `assertMsg` rejection (`submitMustFail`) |

## Run it

```bash
# from this directory
daml build                       # produces .daml/dist/asset-tests-1.0.0.dar (optional but recommended)

dpm trace test .                 # run every Script test, render trees, gate on failures
dpm trace test . --no-trees      # summary + failures only (compact CI logs)
dpm trace test . --print-json    # machine-readable report
dpm trace test . -p testSplit    # run a subset by pattern
```

If the `dpm` plugin is not on your PATH, run the CLI directly:

```bash
PYTHONPATH=../dpm-trace/src python3 -m dpm_trace.cli test . --daml daml
```

Pass `--dar .daml/dist/asset-tests-1.0.0.dar` to verify failure text against the
compiled package with `damlc inspect` before resolving it against local sources.

## Demo: catching a regression

`./run-demo.sh` shows the full story end to end: a green run, then it weakens
`ensure quantity > 0` to `>= 0`, re-runs, and the zero-quantity guard test fails
with a source-mapped diagnostic and a non-zero exit code — then it reverts.

```
FAIL  testCannotIssueZero
      message: ... Expected submit to fail but it succeeded
      daml/Test.daml:63:3
      > 63 |   submitMustFail issuer do
               ^
```

## Integration tests (real Canton)

The `itests/` directory holds `lit` integration tests that run against a **real
local Canton node**. `dpm trace test --integration` boots Canton, deploys this
package's DAR, allocates `Alice`/`Bob`, runs the suite, and tears Canton down:

```bash
dpm trace test . --integration itests \
  --canton-jar "$HOME/.daml/sdk/3.4.11/canton/canton.jar" \
  --daml daml
```

Each test submits against the live ledger and asserts on the resulting trace —
e.g. `itests/asset-issue-to-bob.test` issues an Asset owned by Bob and checks
Bob's participant projection sees it. Needs `lit` and `FileCheck` on PATH; CI is
in `.github/workflows/integration.yml`.

## CI/CD

`.github/workflows/ci.yml` is the unit-test gate. The key line is just:

```bash
dpm trace test . --files daml/Test.daml --junit dpm-trace-results.xml --no-trees
```

A non-zero exit fails the job; the JUnit XML is uploaded for the test-report UI;
and any failure is printed with its source location in the job log.
