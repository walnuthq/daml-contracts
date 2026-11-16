# AGENTS.md

Guidance for agents working in this repository.

This package is the canonical copy of `examples/asset` in [walnuthq/dpm-trace](https://github.com/walnuthq/dpm-trace). Its `tests/check-examples-sync.py` fails when the two drift, and its integration workflow checks this repo out and runs the suite here.

## Rules

- A change here goes to `dpm-trace/examples/asset` too: copy `daml.yaml`, `multi-package.yaml`, `daml/`, `unittests/`, `itests/lit.cfg.py` and `itests/asset-create.test`. Check dpm-trace's goldens and `tests/daml-script-test.test`, which pin line numbers in `Asset.daml` and the number of passing tests.
- Keep the docs in step. The user docs in [walnuthq/docs](https://github.com/walnuthq/docs) (`docs-canton/`) show output from this package. Any change to a version (SDK, DPM, Canton), the build steps, a test name or count, or a line that shows up in a source-mapped failure needs a check of those pages, and the same update there. Re-run the commands a page shows and copy the new output rather than editing it by hand.
- Git DAR dependencies (`git:` lines in `daml.yaml`) are fetched by `dpm install package`, not by `dpm build`. Run it in the root and in `unittests/` before building on a new machine or in CI.
