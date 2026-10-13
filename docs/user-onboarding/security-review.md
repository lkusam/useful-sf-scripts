# Security review notes

Scan results and justifications for the AppExchange security review, for the code in `force-app`.

## How to scan

Needs Salesforce CLI v2 with the Code Analyzer plugin, and Java 11+. On Apple Silicon, use a native (arm64) JDK.

```bash
sf code-analyzer run --workspace force-app --rule-selector AppExchange --rule-selector Recommended --rule-selector sfge --output-file code-analyzer-report.html
```

Generate the report fresh for each submission. Don't commit it, because it contains local file paths.

## Current results

| Severity | Count | Summary |
|---|---|---|
| Critical | 0 | |
| High | 2 | Graph Engine FLS findings on the two deliberate uniqueness checks. Justified below. |
| Moderate | 26 | 4 security-relevant ones, justified below. The rest are code-size and complexity metrics. |
| Low | 328 | ApexDoc comments and SLDS 2 hard-coded value lint, with fallback values after styling hooks. No security impact. |

The Graph Engine found **no CRUD/FLS violations** in any query or DML the user drives. All browsing queries and all DML run in `USER_MODE`, so Salesforce enforces CRUD, FLS and sharing for the running user.

## Justified findings

### ApexFlsViolation: `User.Username` and `User.CommunityNickname` (High)

**Where:** `UserOnboardingController.createUser` (the duplicate-username check) and `uniqueNickname`.

**Why it's safe:**
- **The query must see every user.** Usernames and nicknames have to be unique across the whole org. A user-mode query would skip users hidden by the caller's sharing or FLS. The tool would then report "available" for a value that's taken, and the user insert would fail later.
- **Nothing is exposed.** The queries only check whether a match exists. No other user's data is returned to the caller.
- **Values in messages come from the caller.** The only value that ever appears in a message is the username built from the email the admin just typed.
- **These are the only system-mode reads besides two others.** The other system-mode reads are the running user's *own* permissions and assignments (`resolveAccess`, `missingPlatformPermissions`) and licence counts (`UserLicense`, `PermissionSetLicense`), which only become numbers in the UI.

### MissingNullCheckOnSoqlVariable: `username` (Moderate)

`username` comes from `buildUsername`, which can't return null: `validate()` has already rejected a blank email. This is a false positive.

### ProtectSensitiveData on custom metadata fields (Moderate)

**Flagged fields:** `User_Onboarding_Access__mdt.Access_Type__c`, `Access_Value__c`, and `User_Onboarding_Setting__mdt.Send_Password_Reset_Email__c`.

**Why it's a false positive:** the rule matches field names containing "access" or "password". None of these fields store secrets.
- `Access_Type__c` is a picklist: Username, Profile or Permission Set.
- `Access_Value__c` is a username, profile name or permission set name used for matching.
- `Send_Password_Reset_Email__c` is a checkbox.

**Why the types stay Public:** they must remain Public so admins in installing orgs can manage the records in Setup.

### @lwc/lwc/no-async-operation: `setTimeout` (Moderate)

`userOnboarding.js` delays the search 300 ms after the last keystroke, so Apex isn't called on every key press. The timer is cleared on each new keystroke, and a request counter discards stale results. It's a standard debounce, and nothing else is timed asynchronously.

### Code metrics (Moderate): complexity, size, Boolean parameters, parameter count

`CognitiveComplexity`, `CyclomaticComplexity`, `NcssCount`, `ExcessiveParameterList` and `AvoidBooleanMethodParameters` measure maintainability, not security. `AvoidBooleanMethodParameters` fires on the `@AuraEnabled` DTO properties, which have to be Boolean for the LWC.

## Design points reviewers usually ask about

| Topic | How it's handled |
|---|---|
| **CRUD/FLS and sharing** | The class is `with sharing`. Every user-driven SOQL uses `WITH USER_MODE`, and every DML uses `AccessLevel.USER_MODE`. |
| **Authorisation** | Every `@AuraEnabled` method except `getAccessInfo` first calls `requireAccess()`; `getAccessInfo` only reports the caller's own access flags. That checks for a matching active `User_Onboarding_Access__mdt` rule and for the platform permissions Manage Users, View Setup and Assign Permission Sets. The checks are repeated on the server for every call. |
| **SOQL injection** | All values are bound. Search terms are LIKE-escaped. The only dynamic SOQL (`queryCloneUser`) builds its field list from describe results and a constant list, never from user input. |
| **XSS** | The LWC renders all data through template bindings, with no `innerHTML` or `lwc:dom="manual"`. |
| **Secrets** | None are stored. Password resets use `System.resetPassword`, so Salesforce sends the email and the tool never sees a password. |
| **Third-party code** | None; no static resources or external scripts. |
