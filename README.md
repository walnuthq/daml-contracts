# asset — Daml Script unit and Canton integration tests with `dpm trace test`

A small, self-contained Daml package that shows how to run **unit tests** (on
the in-memory IDE ledger) and **integration tests** (against a real local
Canton node) through `dpm trace test`, and wire both into CI/CD.

`dpm trace test` wraps `daml test` and adds what it does not:

- renders each script's **transaction tree** (creates, exercises, archives,
  `submitMustFail` guards, parties, arguments, source locations);
- maps every **failed test back to source** — the test call site *and* the
  contract invariant (`assertMsg`/`abort`/`ensure`) that rejected it;
- returns a **non-zero exit code** when any test fails, so it gates CI;
- emits a machine-readable report with `--print-json` and JUnit XML with
  `--junit`.

## Layout

```
daml/Asset.daml                  IOU-style Asset: Transfer, Split, Burn, ensure quantity > 0
unittests/daml/Test.daml         Script unit tests — happy paths + submitMustFail guards
unittests/daml/FailureDemo.daml  one deliberately failing test (non-gating source-mapped demo)
multi-package.yaml               builds asset and unittests together
itests/                          lit integration tests against a real local Canton
.github/workflows/     ci.yml = unit gate, integration.yml = integration gate
run-demo.sh            green run -> inject a regression -> red run -> revert
```

## Unit tests

Run on the in-memory IDE ledger — **no Canton node** — so they run anywhere
a Daml toolchain runs.

The Script tests are a separate package, `unittests/`, that depends on the
asset DAR. That keeps daml-script out of the DAR uploaded to a ledger. Build
both first:

```bash
dpm build --all
dpm trace test unittests                 # run every Script test, render trees, gate on failures
dpm trace test unittests --no-trees      # summary + failures only (compact CI logs)
dpm trace test unittests --print-json    # machine-readable report
dpm trace test unittests -p testSplit    # run a subset by pattern
```

| Test | What it exercises |
| --- | --- |
| `testIssue` | create, payload/observer visibility |
| `testTransfer` | consuming exercise → archive + child create |
| `testSplit` | exercise → two child creates |
| `testCannotIssueZero` | `ensure quantity > 0` rejection (`submitMustFail`) |
| `testStrangerCannotTransfer` | authorization rejection (`submitMustFail`) |
| `testBadSplitFails` | in-choice `assertMsg` rejection (`submitMustFail`) |

To map a failure into the contract as well as the test, pass the asset
package's sources and DAR. `--daml-yaml` replaces the default, so name both:

```bash
dpm trace test unittests \
  --daml-yaml unittests/daml.yaml --daml-yaml daml.yaml \
  --dar .daml/dist/asset-1.0.0.dar
```

The DAR is verified with `damlc inspect` before local sources are searched.

## Integration tests

Run against a **real local Canton node** that `dpm trace test --integration`
boots, deploys this package's DAR to, allocates `Alice`/`Bob` on, runs the
suite over, and tears down. (The `itests/` scaffolding came from
`dpm trace test --init`.)

```bash
dpm trace test . --integration itests \
  --canton-jar "$HOME/.dpm/cache/components/canton-open-source/3.5.1/lib/canton-open-source-3.5.1.jar" \
  --daml dpm \
  --parties Alice@1,Bob@2,Issuer@1 \
  --verbose
```

Each test submits against the live ledger and asserts on the trace:

- `asset-create.test` — issue an Asset and trace the committed transaction.
- `asset-issue-to-bob.test` — **cross-participant**: Alice (participant1)
  issues an Asset owned by Bob (participant2); the same update is traced from
  Bob's separate participant via `%ledger2` (run with `--parties Alice@1,Bob@2`).
- `asset-split-rejected.test` — a Split the contract rejects; the live
  rejection is captured and mapped back to the Asset source line.
- `xfail-create-zero-asset.test` — **XFAIL**: a submit the `ensure` guard
  rejects; marked `# XFAIL: .*` so the failure output is visible in CI without
  breaking the gate.

`--verbose` passes `-vv` to lit (per-test command output, including XFAIL
failures) and prints the Canton log tail on failure — the CI job uses it so
every failed test is fully diagnosable in the job log.

Needs `lit` and `FileCheck` on PATH.

## CI/CD

Two GitHub Actions workflows, both fetching `dpm-trace` via `actions/checkout`:

- **`ci.yml`** — the unit gate, runs on every push/PR. The key line:

  ```bash
  dpm trace test unittests --files daml/Test.daml \
    --daml-yaml unittests/daml.yaml --daml-yaml daml.yaml \
    --dar .daml/dist/asset-1.0.0.dar --junit dpm-trace-results.xml --no-trees
  ```

  A non-zero exit fails the job; the JUnit XML is uploaded for the test-report
  UI; any failure is printed with its source location in the job log. A second
  non-blocking step runs `FailureDemo.daml` so the source-mapped failure output
  is visible without failing the build.

- **`integration.yml`** — the integration gate, runs on pushes to `main` and
  on demand. Boots Canton, runs the `itests/` suite with `--verbose`, and gates
  on the lit exit code.

## Demo: catching a regression

`./run-demo.sh` shows the full story end to end: a green run, then it weakens
`ensure quantity > 0` to `>= 0`, re-runs, and the zero-quantity guard test
fails with a source-mapped diagnostic and a non-zero exit code — then it
reverts.

```
FAIL  testCannotIssueZero
      message: ... Expected submit to fail but it succeeded
      daml/Test.daml:63:3
      > 63 |   submitMustFail issuer do
               ^
```
