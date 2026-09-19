# Downstream compatibility testing

This directory contains the CPAN Rescue downstream compatibility harness for Devel::CallChecker.

The harness separates discovery from execution. `inventory.json` is a reviewed, dated snapshot of direct CPAN dependents, so a release test run does not silently change when the CPAN river changes.

## Procedure

1. Start with a clean local installation prefix and work directory.
2. Build and test the exact Devel::CallChecker candidate.
3. Install that candidate into the isolated prefix.
4. Resolve each downstream by its CPAN distribution name while recording the reviewed release/version snapshot from `inventory.json`.
5. Preserve commands, environment, exit status, and logs.
6. Re-run every non-pass result against `cpan-0.009` in the same environment before calling it a candidate regression.

## Result classes

- `pass`: downstream suite passes with the candidate.
- `existing_failure`: the same failure reproduces with `cpan-0.009`.
- `candidate_regression`: candidate fails where the baseline passes.
- `blocked`: testing could not complete for an environmental, dependency, fetch, or build reason.

## Files

- `inventory.json`: reviewed direct-dependent snapshot.
- `run-downstream.pl`: conservative runner.
- `results/`: generated summaries and logs.

The initial runner uses `cpanm`. Run it in a disposable workspace or CI job, not against a valuable global Perl installation.

Example smoke test:

    perl maint/downstream/run-downstream.pl --only Devel-CallParser

A non-pass result is provisional until the same downstream is tested against the `cpan-0.009` baseline.


The runner passes the CPAN distribution name (for example `Devel-CallParser`) to `cpanm`. A release label such as `Devel-CallParser-0.004` is metadata, not a valid generic cpanm lookup target. A future inventory can provide an explicit `cpan_target` when an exact author/path tarball is required.
