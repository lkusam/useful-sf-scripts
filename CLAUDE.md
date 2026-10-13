# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A Salesforce DX project (API 64.0) with two independent parts:

- `force-app/`: the **User Onboarding** utility bar app (LWC + Apex + custom metadata). It is the only package directory, so everything in it gets deployed and packaged.
- `scripts/`: standalone helper scripts that are never deployed (`scripts/apex` for Anonymous Apex, `scripts/shell` for the batch runner).

The only tooling is the Salesforce CLI (`sf`). There is no npm/lint setup; LWC isn't unit-tested locally.

## Commands

Always pass `--target-org` explicitly. The user's global default org may be a client org.

```bash
# Compile + run the Apex tests without changing the org (catches compile errors)
sf project deploy validate --source-dir force-app --target-org dev --test-level RunSpecifiedTests --tests UserOnboardingControllerTest

# Deploy a validation that passed (job id printed by validate)
sf project deploy quick --job-id <id> --target-org dev

# Run a single test method against an org where the code is deployed
sf apex run test --tests UserOnboardingControllerTest.createUserClonesProfileRoleManagerAndAccess --target-org dev --result-format human --synchronous
```

## User Onboarding architecture

Docs for users and admins live in `docs/user-onboarding/`. The parts that span several files:

- **Contract between LWC and Apex:** `userOnboarding.js` calls `UserOnboardingController` imperatively. The DTO property names (`AccessInfo`, `UserOption`, `CloneSource`, `OnboardingRequest`, `OnboardingResult`) are the interface, so renaming one means changing both sides.
- **Two-layer access:** a matching active `User_Onboarding_Access__mdt` rule with `Can_Create__c` is required, *and* the Apex runs in `USER_MODE`, so the user also needs Manage Users / View Setup / Assign Permission Sets (`missingPlatformPermissions` checks these up front). `SYSTEM_MODE` is used only for the running user's own access, org-wide uniqueness checks and licence counts.
- **createUser order:**
  1. Validate access, input and licences.
  2. Insert the User. Failure throws, and the whole transaction rolls back.
  3. Partial-success inserts of licences, then permission sets, then permission set groups, then group members. Each failure becomes a `warnings` entry.
  4. Send the onboarding emails, last.
- **Tests can't insert custom metadata or change licence counts.** `UserOnboardingControllerTest` injects in-memory records through the `@TestVisible` overrides (`accessRulesOverride`, `settingOverride`, `missingPermissionOverride`, `userLicenseAvailableOverride`). Test-created users don't consume licences, but tests *do* see the org's real licence counts, which is why `grantAccess()` fakes free licences.
- **Utility bar styling:** the utility bar uses synthetic shadow, so Salesforce's global CSS can leak in. Avoid generic class names and elements (e.g. `footer`); the footer is deliberately `onb-footer`.

## Scripts

`scripts/shell/runapexfile.sh` runs an Anonymous Apex file against an org repeatedly, sleeping between runs. This works around governor limits without a Batch Apex class.

- Its settings are hard-coded variables at the top: `ORG_ALIAS`, `APEX_SCRIPT_PATH`, `NUM_RUNS`, `Sleep_Timer`.
- Paths are relative to the script itself, so it can be run from anywhere. Logs go to `scripts/shell/logs/`, which git ignores.
- It stops on the first failed run.

The `scripts/apex/*.apex` files are Anonymous Apex for `sf apex run`. Each should do one bounded chunk of work per run, so repeated runs make progress. The sample `test.apex` really changes data (it appends `.invalid` to Contact emails). Never run it without confirming the target org.

## Conventions

- No `Co-Authored-By: Claude` trailers or "Generated with Claude Code" lines in commits/PRs.
- Custom metadata fields are `SubscriberControlled`, so admins in installing orgs can edit the shipped records (needed for packaging).
