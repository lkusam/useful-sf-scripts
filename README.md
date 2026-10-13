# This is repo for a collection of useful Salesforce Tips and Tricks.

## Run Anonymous APEX in Batch style

This is useful when you need to run a Anonymous APEX but similar to Batch Jobs but don't want to write a full APEX class and handle it ? This will help.

### How it works:

This uses a simple shell script where you provide the number of seconds it needs to sleep and number of time the APEX script needs to be executed and vola!! That's it.

### How to run it

1. Authenticate an org with the Salesforce CLI.
2. Clone the repo.
3. Make the script executable: `chmod +x scripts/shell/runapexfile.sh` on **Mac or Linux**. On **Windows**, run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` in PowerShell.
4. Put the Apex script that does the DML in `scripts/apex`. See `scripts/apex/test.apex` for a sample.
5. Update the variables at the top of `scripts/shell/runapexfile.sh`:

   1. Number of runs
   2. Sleep timer
   3. Org alias
   4. Script path (relative to the script)

6. Run it from anywhere: `./scripts/shell/runapexfile.sh`. Logs are written to `scripts/shell/logs/`.

## User Onboarding utility bar (LWC)

A Lightning utility bar wizard that onboards a new user by cloning an existing one. It copies the profile, role, permission sets, permission set groups, licences, and group/queue memberships, assigns a manager, and sends password reset and email verification emails. Custom metadata controls who can use it and how usernames are built.

| Guide | |
|---|---|
| [Overview](docs/user-onboarding/README.md) | What it does and how it fits together |
| [Installation](docs/user-onboarding/installation.md) | Deploy from source or install as an unlocked package |
| [Admin guide](docs/user-onboarding/admin-guide.md) | Access rules, username suffix, onboarding emails, utility bar setup |
| [User guide](docs/user-onboarding/user-guide.md) | Using the wizard step by step |
| [Troubleshooting](docs/user-onboarding/troubleshooting.md) | Common errors and fixes |

### Install

**Free** · never requires payment · unlocked package v1.0.0

<p>
  <a href="https://login.salesforce.com/packaging/installPackage.apexp?p0=04tak000000nzojAAA"><img src="docs/images/install-production.svg" alt="Install in Production" width="260" height="48"></a>
  &nbsp;
  <a href="https://test.salesforce.com/packaging/installPackage.apexp?p0=04tak000000nzojAAA"><img src="docs/images/install-sandbox.svg" alt="Try it in a Sandbox" width="260" height="48"></a>
</p>

Click a button, log in to **your** org, and choose **Install for Admins Only**. No password is needed. Package version ID: `04tak000000nzojAAA`.

Or use the CLI:

```bash
sf package install --package 04tak000000nzojAAA --target-org your_org_alias --wait 20
```

Then follow [After installing](docs/user-onboarding/installation.md#after-installing): assign the permission set and add the component to your app's utility bar. To deploy from source instead, see [Installation](docs/user-onboarding/installation.md).
