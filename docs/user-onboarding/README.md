# User Onboarding

A Lightning utility bar tool for Salesforce admins. To onboard a new user, you clone an existing user who already has the right access. Fill in a short wizard and the tool creates the user with the same profile, role, permissions and groups, assigns a manager, and sends the onboarding emails.

## What it does

| You provide | The tool does |
|---|---|
| The user to clone, found by name, username or email | Copies their profile, role, locale settings, feature licences, permission set licences, permission sets and permission set groups |
| First name, last name, email | Builds the username from the email plus your configured suffix, and generates an alias and nickname |
| *(Optional)* a manager email | Uses that manager. If you leave it blank, uses the clone user's manager |
| *(Optional)* groups and queues | Starts from the clone user's memberships; you can remove or add groups and queues |
| — | Sends a password reset email and an email verification link |

If an individual permission, group or email fails, the user is still created. Each failure is listed on the success screen so you can fix it by hand.

## Guides

| Guide | For | Covers |
|---|---|---|
| [Installation](installation.md) | Admins and developers | Getting it into an org: from source or as an unlocked package |
| [Admin guide](admin-guide.md) | Salesforce admins | Who can use it, username suffixes, onboarding emails, the utility bar |
| [User guide](user-guide.md) | People onboarding users | Walking through the wizard step by step |
| [Troubleshooting](troubleshooting.md) | Everyone | Common errors and fixes |

## How it fits together

```
Utility bar
  └─ userOnboarding (LWC wizard)  ── userOnboardingStepper (progress indicator)
        │  calls
        ▼
  UserOnboardingController (Apex)
        │  reads                                   │  creates
        ├─ User_Onboarding_Access__mdt  (who)      ├─ User
        └─ User_Onboarding_Setting__mdt (how)      ├─ PermissionSetLicenseAssign / PermissionSetAssignment
                                                   ├─ GroupMember (groups and queues)
                                                   └─ password reset + verification emails
```

- **Access control has two layers.** Custom metadata decides who may use the tool. The Apex also runs in **user mode**, so the person's own Salesforce permissions still apply. The tool can never give anyone more than they already have.
- **The work is done in a set order.** The user is created first. Then permission set licences are assigned, because some permission sets need them, followed by permission sets, permission set groups and groups/queues. The emails go last, so the user's access is in place before they sign in.

## Source

| Path | What |
|---|---|
| `force-app/main/default/lwc/userOnboarding` | The wizard UI |
| `force-app/main/default/lwc/userOnboardingStepper` | Step indicator used by the wizard |
| `force-app/main/default/classes/UserOnboardingController.cls` | All server logic |
| `force-app/main/default/classes/UserOnboardingControllerTest.cls` | Apex tests |
| `force-app/main/default/objects/User_Onboarding_*__mdt` | The two custom metadata types |
| `force-app/main/default/customMetadata` | Default records (System Administrator access, Default settings) |
| `force-app/main/default/layouts` | Page layouts for both custom metadata types |
| `force-app/main/default/permissionsets/User_Onboarding_Admin.permissionset-meta.xml` | Apex class access |
