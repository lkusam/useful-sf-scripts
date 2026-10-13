# User guide

How to onboard a new user with the **User Onboarding** utility.

**Before you start:** have the new person's name and email, and know an existing user with the same job. You'll copy that user's access. If you can't see **User Onboarding** in the utility bar at the bottom of the app, ask your admin to give you access (see the [Admin guide](admin-guide.md)).

Click **User Onboarding** in the utility bar. The progress indicator at the top shows four steps. You can click a completed step to go back to it.

## Step 1: Clone from

1. Type at least 2 characters of the existing user's **name, username or email**.
2. Pick them from the results. Each card shows their profile and role.
3. Check the summary: profile, role, manager, and how many permission sets, permission set groups, licences, and groups/queues will be copied. Expand **See what will be copied** to see the names.

If the user you pick is on a licence type with none left, a **No … licences left** card replaces the summary. Click **Pick a different user**, or ask your admin to free up a licence.

> Choose someone whose access matches the new person's job exactly. The new user gets everything this user has.

## Step 2: New user

Enter **First name**, **Last name** and **Email**. All three are required.

The **username preview** below shows what the username will be: the email plus your org's suffix, if one is set. It must be unique across all Salesforce orgs.

## Step 3: Extras (optional)

**Manager email**
- Leave it blank to use the clone user's manager. The step shows who that is.
- Or enter a manager's email. When you leave the field, the tool looks the manager up and shows them. If no active user has that email, you can't continue until you fix or clear it.

**Groups & queues**
- The clone user's groups and queues are already selected. Click **×** on a pill to remove one.
- Use the filter to find more, and click one to add it. Badges show whether each is a **Group** or a **Queue**.

## Step 4: Review

1. Check each section. Use **Edit** to jump back to any step.
2. The note at the bottom says which emails the new user will receive.
3. Click **Create user**.

## After creating

The success screen shows:
- The new **username**.
- How many permission sets, permission set groups, licences and groups/queues were assigned.
- Which onboarding emails were sent.
- **Items that need your attention**, if any. Something couldn't be assigned (for example, a permission set whose licence has run out) or an email failed. The user still exists; fix those items on the user record.

Then:
- **Open user record** goes to the new user in Setup.
- **Onboard another** starts over.

## What the new user receives

With the default settings:
1. A **password reset** email with a link to set their password and sign in.
2. An **email verification** link to confirm their email address.

Your admin may have turned these off, for example in a sandbox. In that case, the review step says so, and you'll need to share sign-in details another way.
