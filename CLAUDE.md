# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A small collection of Salesforce utility scripts. There is no build system, package manager, linter, or test suite. The only external dependency is the Salesforce CLI (`sf`), and the target org must already be authenticated with it.

## Main tool: batch-style Anonymous Apex runner

`shell/runapexfile.sh` runs an Anonymous Apex file against an org a set number of times, sleeping between runs. Repeating a DML script this way works around governor limits without writing a Batch Apex class.

- Settings are hard-coded shell variables at the top of the script, with no CLI arguments: `ORG_ALIAS`, `APEX_SCRIPT_PATH`, `NUM_RUNS`, `Sleep_Timer` (seconds).
- Each iteration runs `sf apex run -o $ORG_ALIAS --file $APEX_SCRIPT_PATH`. All output is appended to `./logs/run_log_<timestamp>.log`. The loop stops on the first non-zero exit code.
- **Paths are relative to the current working directory.** The default `APEX_SCRIPT_PATH="../apex/test.apex"` assumes you run the script from inside `shell/`, and `logs/` is created there too:

```bash
cd shell && ./runapexfile.sh
```

## Apex scripts (`apex/`)

These are Anonymous Apex snippets (`.apex`) meant to be passed to `sf apex run`. They are not deployable classes. Each one should do one bounded chunk of work per run (for example, a query that excludes records already processed) so that running it repeatedly makes progress. `test.apex` is the sample: it appends `.invalid` to every Contact email that doesn't already end with it. That is real DML, so never run it against an org without confirming the target.

## Notes

- `.sfdx/` contains local Salesforce extension tooling state and is not project source.
