# Admin guide

Everything is configured with two custom metadata types, so there's no code to change. Find them in Setup → **Custom Metadata Types** → **Manage Records**.

## Who can use the tool: `User Onboarding Access`

Each record is a rule. A person can use the tool when they match at least one rule that is **Active** with **Can Create** ticked.

| Field | Meaning |
|---|---|
| **Access Type** | What to match on: `Username`, `Profile` or `Permission Set` |
| **Access Value** | The username, profile name (e.g. `System Administrator`), or permission set API name (e.g. `HR_Onboarding`). Not case-sensitive. |
| **Can Create** | Lets matching users open the tool and create users. On by default; untick it to pause a rule without deleting it. |
| **Active** | Only active rules count |

The `Permission Set` type matches sets assigned directly or through a permission set group, and also the group's own API name.

**Shipped default:** `System Administrators`, which gives the System Administrator profile access.

**Examples:**

| Goal | Access Type | Access Value |
|---|---|---|
| The HR team can onboard | Permission Set | `HR_Onboarding` |
| All system admins can onboard | Profile | `System Administrator` |
| One specific person can onboard | Username | `jane.admin@acme.com` |

> **Rules don't grant platform permissions.** The tool runs in user mode, so a person also needs Salesforce's own **Manage Users**, **View Setup and Configuration** and **Assign Permission Sets**, plus the **User Onboarding Admin** permission set. A rule can only narrow access, never widen it.

## What happens when something isn't right

The tool checks for problems as early as it can, so nobody fills in the whole wizard only to hit an error at the end.

| Situation | When it's caught | What the person sees | Is a user created? |
|---|---|---|---|
| No matching active rule | When the tool opens | "This tool is not available to you", with a note to ask an admin | No |
| Has a rule but lacks Manage Users, View Setup or Assign Permission Sets | When the tool opens | "A few permissions are missing", listing exactly which ones | No |
| No licences left for the picked user's licence type | Step 1, as soon as the clone user is picked | A card takes over step 1, explains which licence ran out and the options, and offers **Pick a different user**. **Next** stays disabled. | No |
| Only a few licences left (3 or fewer) | Step 1 | An info notice with the remaining count | Yes |
| A permission set licence the clone user has is used up | Step 1 | A warning naming the licence | Yes, without that licence and the permission sets that need it |
| Licences ran out between step 1 and **Create user** | On create, re-checked before anything is saved | "No … licences are left" | No |
| Username taken here or in another org | On create | A clear message suggesting a **Username Suffix** | No |
| Any other error while creating the user | On create | "The user was not created" with Salesforce's reason; the form keeps everything so you can fix it and retry | No. Nothing is saved, because the whole create is rolled back. |
| One permission set, group or queue can't be assigned | After the user is created | Listed under **Items that need your attention** on the success screen | Yes, with everything else assigned |
| An onboarding email fails | After the user is created | Listed under **Items that need your attention** | Yes |

## How the tool behaves: `User Onboarding Setting`

Only the record named **Default** is used. If it's missing or inactive, the tool uses no suffix, with the password reset and verification emails turned on.

| Field | Default | Meaning |
|---|---|---|
| **Username Suffix** | blank | Added to the email to make the username. `.uat` turns `jane@acme.com` into `jane@acme.com.uat`. Usernames must be unique across *all* Salesforce orgs, so sandboxes usually need a suffix. |
| **Send Password Reset Email** | on | Resets the password and emails a link so the user sets their own. |
| **Send Verification Email** | on | Emails a link for the user to confirm their email address. |
| **Send Welcome Email** | on | The standard Salesforce new-user email. **Ignored while Send Password Reset Email is on**, because the reset would invalidate the welcome email's link. |
| **Active** | on | When off, the built-in defaults above are used. |

### Recommended settings by environment

| Environment | Suffix | Password reset | Verification | Why |
|---|---|---|---|---|
| Production | blank | on | on | Real users sign in straight away |
| Full / partial sandbox | e.g. `.uat` | **off** | **off** | Avoid emailing real people from a test org |
| Developer Edition / scratch org | e.g. `.dev` | your call | your call | Only use addresses you own |

## What gets copied from the clone user

| Copied | Not copied |
|---|---|
| Profile, role | Title, phone numbers |
| Time zone, locale, language, email encoding | Federation ID, employee number |
| Company, department, division, address | Profile-owned permissions (these come with the profile anyway) |
| `UserPermissions*` feature licences (e.g. Marketing User, Knowledge User) | Indirect group membership (e.g. through roles or nested groups) |
| Permission set licences, permission sets, permission set groups | |
| Direct public group and queue memberships, which the wizard lets you edit | |

**Manager:** the manager email entered in the wizard is used if one was given. Otherwise the new user gets the clone user's manager.

## Utility bar placement

Setup → **App Manager** → your app → ▾ **Edit** → **Utility Items** → **Add Utility Item** → **User Onboarding**.

- Width about **420**, height about **640**.
- Leave **Start automatically** off; the tool loads when it's opened.
- To use it in more than one app, add it to each app's utility bar.

It can also be placed on a Lightning **App page** or the **Home page** with the Lightning App Builder.
