# This is repo for a collection of useful Salesforce Tips and Tricks.

## Run Anonymous APEX in Batch style

This is useful when you need to run a Anonymous APEX but similar to Batch Jobs but don't want to write a full APEX class and handle it ? This will help.

### How it works:

This uses a simple shell script where you provide the number of seconds it needs to sleep and number of time the APEX script needs to be executed and vola!! That's it.

### How to run it

1. A org is authenticated using the Salesforce CLI.
2. Download the repo using `Git Clone` or the shell script
3. Give permission to execute the shell script using `chmod +x script.sh` for **MAC or Linux** for **Windows** using the Powershell `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
4. You need to have you APEX script that does the DML in the `./apex` folder. Please refer to `test.apex` as sample.
5. Update the Sheel variables with your prefrences

   1. Num of Runs
   2. Sleep Timer
   3. Org Alias
   4. Script Path ( This is relative to folder)

6. Execute the script using the terminal `./runapexfile.sh`

## User Onboarding utility bar (LWC)

A Lightning utility bar wizard that onboards a new user by cloning an existing one. It copies the profile, role, permission sets, permission set groups, licences, and group/queue memberships, assigns a manager, and sends password reset and email verification emails. Custom metadata controls who can use it and how usernames are built.

| Guide | |
|---|---|
| [Overview](docs/user-onboarding/README.md) | What it does and how it fits together |
| [Installation](docs/user-onboarding/installation.md) | Deploy from source or install as an unlocked package |
| [Admin guide](docs/user-onboarding/admin-guide.md) | Access rules, username suffix, onboarding emails, utility bar setup |
| [User guide](docs/user-onboarding/user-guide.md) | Using the wizard step by step |
| [Troubleshooting](docs/user-onboarding/troubleshooting.md) | Common errors and fixes |

Quick start for a sandbox or dev org. For production and validate-first steps, see [Installation](docs/user-onboarding/installation.md):

```bash
sf project deploy start --source-dir force-app --target-org your_org_alias
```
