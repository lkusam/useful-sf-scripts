# Installation

There are three ways to install. Pick based on who is installing:

| Option | Best for | Upgradable |
|---|---|---|
| [A. Deploy from source](#a-deploy-from-source) | Developers, testing, your own orgs | Redeploy |
| [B. Unlocked package](#b-unlocked-package) | Sharing with other orgs through an install link | Yes, install the new version |
| [C. Unmanaged package](#c-unmanaged-package) | A one-off copy | No |

## Prerequisites

- **Salesforce CLI v2** (`sf`). On Apple Silicon Macs, use the native installer or `npm install --global @salesforce/cli`. Old v7 `sfdx` installs fail with "Bad CPU type in executable"; see [Troubleshooting](troubleshooting.md#bad-cpu-type-in-executable).

  ```bash
  sf --version
  ```

  This should print `@salesforce/cli/2.x`, and on Apple Silicon the platform should be `darwin-arm64`.
- **An org to install into.** For testing, a free Developer Edition (`https://developer.salesforce.com/signup`) works well.
- **Admin access** in the target org.

## A. Deploy from source

1. Get the code and log in to the org:

   ```bash
   git clone https://github.com/lkusam/useful-sf-scripts.git
   ```

   ```bash
   cd useful-sf-scripts
   ```

   ```bash
   sf org login web --alias my-org
   ```

2. **Validate first.** This compiles everything and runs the Apex tests without changing the org:

   ```bash
   sf project deploy validate --source-dir force-app --target-org my-org --test-level RunSpecifiedTests --tests UserOnboardingControllerTest
   ```

3. **Deploy.** Reuse the successful validation with the job ID it printed:

   ```bash
   sf project deploy quick --job-id <job-id-from-validate> --target-org my-org
   ```

   Or deploy directly:

   ```bash
   sf project deploy start --source-dir force-app --target-org my-org --test-level RunSpecifiedTests --tests UserOnboardingControllerTest
   ```

   Production orgs require the test flags. Sandboxes and Developer Edition orgs don't.

4. Continue with [After installing](#after-installing).

> **Always pass `--target-org`.** If your CLI default org is a client or production org, a command without it goes there.

## B. Unlocked package

You build a package version once; anyone can then install it from a link.

### Build it (once per version)

1. **Turn on Dev Hub** in an org you own (production or Developer Edition): Setup → **Dev Hub** → **Enable Dev Hub**, and also **Enable Unlocked Packages and Second-Generation Managed Packages**.
2. Log in to that org as the Dev Hub:

   ```bash
   sf org login web --alias devhub --set-default-dev-hub
   ```

3. **Create the package.** This happens only once, and it records the package ID in `sfdx-project.json`:

   ```bash
   sf package create --name "User Onboarding" --package-type Unlocked --path force-app --no-namespace --target-dev-hub devhub
   ```

4. In `sfdx-project.json`, add `"versionNumber": "1.0.0.NEXT"` to the `force-app` entry.
5. **Build a version.** This runs the Apex tests and needs 75% coverage:

   ```bash
   sf package version create --package "User Onboarding" --installation-key-bypass --code-coverage --wait 30 --target-dev-hub devhub
   ```

6. **Promote it** so it can be installed in production:

   ```bash
   sf package version promote --package "User Onboarding@1.0.0-1" --target-dev-hub devhub
   ```

### Install it

Use the `04t…` subscriber version ID printed by step 5:

- Production / Developer Edition: `https://login.salesforce.com/packaging/installPackage.apexp?p0=04t...`
- Sandbox: `https://test.salesforce.com/packaging/installPackage.apexp?p0=04t...`

Or install from the CLI:

```bash
sf package install --package 04t... --target-org my-org --wait 20
```

Choose **Install for Admins Only**, then continue with [After installing](#after-installing). To upgrade, install a newer version the same way.

## C. Unmanaged package

In an org where the components are deployed: Setup → **Package Manager** → **New**, add the Apex classes, LWCs, custom metadata types (with their records and page layouts), and the permission set, then **Upload** to get an install link. Installed components can't be upgraded afterwards.

## After installing

These steps are the same for every option:

1. **Assign the permission set** to everyone who will onboard users:

   ```bash
   sf org assign permset --name User_Onboarding_Admin --target-org my-org
   ```

   They also need **Manage Users**, **View Setup and Configuration** and **Assign Permission Sets**. System Administrators already have these.
2. **Add the component to the utility bar.** Go to Setup → **App Manager**, find your app (e.g. Sales), click ▾ → **Edit** → **Utility Items** → **Add Utility Item** → **User Onboarding**. Set the panel width to about **420** and the height to about **640**, then **Save**.
3. **Review the configuration** in the [Admin guide](admin-guide.md): access rules, username suffix and emails. In a sandbox, check the email settings *before* the first real run.
