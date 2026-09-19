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
- `baselines/`: reviewed, classified baseline snapshots suitable for comparison with future candidates.

The initial runner uses `cpanm`. Run it in a disposable workspace or CI job, not against a valuable global Perl installation.

Example smoke test:

    perl maint/downstream/run-downstream.pl --only Devel-CallParser

A non-pass result is provisional until the same downstream is tested against the `cpan-0.009` baseline.


The runner passes the CPAN distribution name (for example `Devel-CallParser`) to `cpanm`. A release label such as `Devel-CallParser-0.004` is metadata, not a valid generic cpanm lookup target. A future inventory can provide an explicit `cpan_target` when an exact author/path tarball is required.

## Recorded baselines

- `baselines/perl-5.40.1-darwin.json`: Perl 5.40.1 on `darwin-thread-multi-2level`; 8 pass and 4 existing failures reproduced against `cpan-0.009`.

## Baseline matrix policy

The maintenance baseline covers representative Perl generations rather than every Perl release supported by the distribution's historical `perl => 5.006` declaration.

The initial matrix is:

| Perl | Role |
| --- | --- |
| 5.16 | older stable generation; exercises substantially older core/XS interfaces |
| 5.24 | middle generation |
| 5.32 | recent pre-5.40 generation |
| 5.40 | current baseline generation |

Run Devel::CallChecker's own test suite and the frozen direct-dependent inventory on each version. A platform-specific failure is recorded rather than silently generalized to other platforms.

Perl 5.40.1 on macOS is already recorded. The remaining 5.16, 5.24, and 5.32 runs may be performed in reproducible CI/container environments; they do not need to be installed into the maintainer's system Perl.

This matrix is a maintenance baseline, not a new statement of minimum supported Perl. The historical `perl => 5.006` metadata remains unchanged until compatibility evidence supports a separate release decision.


## CI baseline runs

The remaining representative baseline versions are run by `.github/workflows/downstream-baseline.yml` on Linux using Perl 5.16, 5.24, and 5.32. The workflow checks out the tagged `cpan-0.009` source into a separate worktree, runs the frozen downstream inventory, and uploads the generated `results/` directory for classification.

A non-pass downstream result does not by itself fail the workflow job: the raw result artifact must be reviewed and classified. Reviewed classifications belong in `baselines/`; generated CI output does not.
