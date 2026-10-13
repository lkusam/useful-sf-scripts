# Troubleshooting

## Installing

### Bad CPU type in executable

```
.../sfdx/client/.../bin/node: Bad CPU type in executable
```

**Cause:** an old Salesforce CLI built for Intel is running on an Apple Silicon Mac without Rosetta. Its auto-updated copy in `~/.local/share/sfdx/client` or `~/.local/share/sf/client` takes priority over a newer install.

**Fix:**

1. Remove the old installer:

   ```bash
   sudo rm -rf /usr/local/bin/sf /usr/local/bin/sfdx /usr/local/lib/sfdx
   ```

2. Remove the auto-updated copies:

   ```bash
   rm -rf ~/.local/share/sfdx/client ~/.local/share/sf/client
   ```

3. Install the current CLI, either with the native installer or with npm:

   ```bash
   npm install --global @salesforce/cli
   ```

4. Open a new terminal and confirm it shows `darwin-arm64`:

   ```bash
   sf --version
   ```

Your org logins are stored in `~/.sf` and `~/.sfdx`, which these steps don't touch.

### AuthDecryptError in `sf org list`

A login saved by an old CLI can't be read by the new one. Log in to that org again:

```bash
sf org login web --alias <alias>
```

### Deploy fails on test coverage in production

Production deploys must run tests. Add `--test-level RunSpecifiedTests --tests UserOnboardingControllerTest`.

## Using the tool

| What you see | Cause | Fix |
|---|---|---|
| "This tool is not available to you" | No rule that is **Active** with **Can Create** ticked matches you | Ask an admin to add or fix a rule for your username, profile or permission set |
| "A few permissions are missing" | You have a rule, but your user lacks Manage Users, View Setup or Assign Permission Sets | Your admin grants the listed permissions; access rules alone aren't enough |
| The utility bar item is missing | It wasn't added to this app, or you lack the **User Onboarding Admin** permission set | See [Installation → After installing](installation.md#after-installing) |
| "No … licences left" after picking a user to clone | Every licence of the clone user's type is in use | Deactivate a user who no longer needs one, buy more, or clone someone on a different licence type |
| "A user with the username … already exists." | That username is taken in this org | Use a different email, or set a **Username Suffix** |
| "The username … is already used in another Salesforce org" | Usernames are unique across all Salesforce orgs | Set a **Username Suffix**, especially in sandboxes |
| "The user was not created" with another reason | Salesforce rejected the new user (e.g. a validation rule on User) | Nothing was saved; fix the cause and press **Create user** again. Your entries are kept. |
| "No active user found with manager email …" | Nobody active has that email | Fix the email, or clear it to use the clone user's manager |
| A warning on the success screen, e.g. "Permission set X: …" | That one assignment failed, often because a permission set licence has run out | The user exists; assign the item by hand once the cause is fixed |
| "Password reset email: …" or "Verification email: …" warning | Salesforce rejected the email request | The user exists; send a reset from the user record (**Reset Password**) |
| The new user got two emails with sign-in links | **Send Welcome Email** and **Send Password Reset Email** were both expected | Only the reset email is sent when both are on; the welcome email is skipped by design |
| No emails arrived in a sandbox | Sandbox **Deliverability** is often "System email only" | Setup → **Deliverability** → **All email** (only if you mean to email real people) |
