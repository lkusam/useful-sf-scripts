@IsTest
private class UserOnboardingControllerTest {
    private static final String DOMAIN = '@uotest.example.com';
    private static final String ADMIN_EMAIL = 'uo.admin' + DOMAIN;
    private static final String CLONE_EMAIL = 'uo.clone' + DOMAIN;
    private static final String MANAGER_EMAIL = 'uo.manager' + DOMAIN;
    private static final String OTHER_MANAGER_EMAIL = 'uo.othermanager' + DOMAIN;
    private static final String NEW_EMAIL = 'nina.newhire' + DOMAIN;
    private static final String PERMISSION_SET_LABEL = 'UO Test Permission Set';
    private static final String GROUP_NAME = 'UO Test Group';
    private static final String QUEUE_NAME = 'UO Test Queue';
    private static final String ROLE_NAME = 'UO Test Role';
    private static final String ADMIN_PROFILE = 'System Administrator';
    private static final String STANDARD_PROFILE = 'Standard User';

    @TestSetup
    static void setup() {
        String token = uniqueToken();
        Id adminProfileId = [SELECT Id FROM Profile WHERE Name = :ADMIN_PROFILE LIMIT 1].Id;
        Id standardProfileId = [SELECT Id FROM Profile WHERE Name = :STANDARD_PROFILE LIMIT 1].Id;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            UserRole role = new UserRole(Name = ROLE_NAME, DeveloperName = 'UO_Test_Role_' + token);
            insert role;

            User admin = buildUser(adminProfileId, 'UOAdmin', ADMIN_EMAIL, token);
            User manager = buildUser(standardProfileId, 'UOManager', MANAGER_EMAIL, token);
            User otherManager = buildUser(standardProfileId, 'UOOtherManager', OTHER_MANAGER_EMAIL, token);
            insert new List<User>{ admin, manager, otherManager };

            User cloneSource = buildUser(standardProfileId, 'UOClone', CLONE_EMAIL, token);
            cloneSource.UserRoleId = role.Id;
            cloneSource.ManagerId = manager.Id;
            cloneSource.Department = 'Onboarding QA';
            cloneSource.CompanyName = 'UO Test Co';
            cloneSource.Title = 'Analyst';
            insert cloneSource;

            PermissionSet permissionSet = new PermissionSet(Label = PERMISSION_SET_LABEL, Name = 'UO_Test_PS_' + token);
            insert permissionSet;
            Group publicGroup = new Group(Name = GROUP_NAME, DeveloperName = 'UO_Test_Group_' + token, Type = 'Regular');
            Group queue = new Group(Name = QUEUE_NAME, DeveloperName = 'UO_Test_Queue_' + token, Type = 'Queue');
            insert new List<Group>{ publicGroup, queue };

            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = cloneSource.Id, PermissionSetId = permissionSet.Id),
                new PermissionSetAssignment(AssigneeId = admin.Id, PermissionSetId = permissionSet.Id)
            };
            insert new List<GroupMember>{
                new GroupMember(GroupId = publicGroup.Id, UserOrGroupId = cloneSource.Id),
                new GroupMember(GroupId = queue.Id, UserOrGroupId = cloneSource.Id)
            };
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Access
    // ---------------------------------------------------------------------------------------------

    @IsTest
    static void noMatchingRuleDeniesEverything() {
        // An inactive rule and a rule without Can Create must both be ignored.
        UserOnboardingController.accessRulesOverride = new List<User_Onboarding_Access__mdt>{
            rule('Profile', ADMIN_PROFILE, true, false),
            rule('Profile', ADMIN_PROFILE, false, true)
        };
        useSettings('.uo' + uniqueToken());
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            UserOnboardingController.AccessInfo info = UserOnboardingController.getAccessInfo();
            Assert.isFalse(info.canCreate, 'No usable rule should mean no access');
            Assert.isTrue(info.missingPermissions.isEmpty(), 'Permissions are only checked for users with a rule');

            try {
                UserOnboardingController.searchUsers('uo.clone');
                Assert.fail('searchUsers should be denied without access');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('do not have access'), e.getMessage());
            }
            try {
                UserOnboardingController.getGroupsAndQueues();
                Assert.fail('getGroupsAndQueues should be denied without access');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('do not have access'), e.getMessage());
            }
            try {
                UserOnboardingController.createUser(newRequest(userByEmail(CLONE_EMAIL).Id));
                Assert.fail('createUser should be denied without access');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('do not have access'), e.getMessage());
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM User WHERE Email = :NEW_EMAIL], 'No user should be created');
    }

    @IsTest
    static void missingPlatformPermissionsBlockTheTool() {
        grantAccess();
        useSettings('.uo' + uniqueToken());
        UserOnboardingController.missingPermissionOverride = new Set<String>{ 'PermissionsManageUsers' };
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            UserOnboardingController.AccessInfo info = UserOnboardingController.getAccessInfo();
            Assert.isTrue(info.canCreate, 'The rule still matches');
            Assert.areEqual(new List<String>{ 'Manage Users' }, info.missingPermissions);
            try {
                UserOnboardingController.createUser(newRequest(userByEmail(CLONE_EMAIL).Id));
                Assert.fail('createUser should be denied while permissions are missing');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Manage Users'), e.getMessage());
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM User WHERE Email = :NEW_EMAIL], 'No user should be created');
    }

    @IsTest
    static void noUserLicencesLeftBlocksCreate() {
        grantAccess();
        useSettings('.uo' + uniqueToken());
        UserOnboardingController.userLicenseAvailableOverride = 0;
        Id cloneId = userByEmail(CLONE_EMAIL).Id;
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            UserOnboardingController.CloneSource source = UserOnboardingController.getCloneSource(cloneId);
            Assert.areEqual(0, source.userLicensesAvailable, 'The clone summary reports no licences left');
            Assert.isNotNull(source.userLicenseName);
            try {
                UserOnboardingController.createUser(newRequest(cloneId));
                Assert.fail('createUser should fail fast when no licences are left');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().startsWith('No ' + source.userLicenseName + ' licences are left'), e.getMessage());
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM User WHERE Email = :NEW_EMAIL], 'No user should be created');
    }

    @IsTest
    static void accessByUsernameAndPermissionSet() {
        User admin = userByEmail(ADMIN_EMAIL);
        String permissionSetName = [SELECT Name FROM PermissionSet WHERE Label = :PERMISSION_SET_LABEL LIMIT 1].Name;
        UserOnboardingController.settingOverride = new User_Onboarding_Setting__mdt(
            Username_Suffix__c = '.ignored', Send_Welcome_Email__c = false, Is_Active__c = false
        );

        System.runAs(admin) {
            UserOnboardingController.accessRulesOverride = new List<User_Onboarding_Access__mdt>{
                rule('Username', admin.Username.toUpperCase(), true, true)
            };
            UserOnboardingController.AccessInfo info = UserOnboardingController.getAccessInfo();
            Assert.isTrue(info.canCreate, 'Username match should be case-insensitive');
            Assert.isTrue(info.missingPermissions.isEmpty(), 'Admins have every required permission');
            Assert.areEqual('', info.usernameSuffix, 'Inactive setting means no suffix');
            Assert.isTrue(info.sendPasswordResetEmail, 'Inactive setting means password reset email on');
            Assert.isTrue(info.sendVerificationEmail, 'Inactive setting means verification email on');
            Assert.isFalse(info.sendWelcomeEmail, 'The password reset email replaces the welcome email');

            UserOnboardingController.accessRulesOverride = new List<User_Onboarding_Access__mdt>{
                rule('Permission Set', permissionSetName.toLowerCase(), true, true)
            };
            Assert.isTrue(UserOnboardingController.getAccessInfo().canCreate, 'Permission set rule should grant access');
        }
    }

    @IsTest
    static void activeSettingsAreApplied() {
        grantAccess();
        UserOnboardingController.settingOverride = new User_Onboarding_Setting__mdt(
            Username_Suffix__c = ' .uat ', Send_Welcome_Email__c = false, Is_Active__c = true
        );
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            UserOnboardingController.AccessInfo info = UserOnboardingController.getAccessInfo();
            Assert.areEqual('.uat', info.usernameSuffix, 'Suffix should be trimmed');
            Assert.isFalse(info.sendWelcomeEmail, 'Welcome email setting should be honoured');
            Assert.isFalse(info.sendPasswordResetEmail, 'Password reset email setting should be honoured');
            Assert.isFalse(info.sendVerificationEmail, 'Verification email setting should be honoured');
        }
        UserOnboardingController.settingOverride = new User_Onboarding_Setting__mdt(
            Send_Welcome_Email__c = true, Send_Password_Reset_Email__c = false, Is_Active__c = true
        );
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            Assert.isTrue(UserOnboardingController.getAccessInfo().sendWelcomeEmail, 'Welcome email is used when reset is off');
        }
        Assert.areEqual('jane@acme.com.uat', UserOnboardingController.buildUsername('  Jane@Acme.com ', ' .uat'));
        Assert.areEqual('jane@acme.com', UserOnboardingController.buildUsername('Jane@Acme.com', null));
        Assert.areEqual('NOBrienS', UserOnboardingController.buildAlias('Nina', 'O\'Brien-Smith'));
        Assert.areEqual('a\\%b\\_c', UserOnboardingController.escapeLike('a%b_c'));
    }

    // ---------------------------------------------------------------------------------------------
    // Read methods
    // ---------------------------------------------------------------------------------------------

    @IsTest
    static void searchUsersFindsByEmailAndIgnoresShortTerms() {
        grantAccess();
        User cloneSource = userByEmail(CLONE_EMAIL);
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            Assert.isTrue(UserOnboardingController.searchUsers(' u ').isEmpty(), 'Terms under 2 chars return nothing');
            Assert.isTrue(UserOnboardingController.searchUsers(null).isEmpty(), 'Null term returns nothing');

            List<UserOnboardingController.UserOption> results = UserOnboardingController.searchUsers('  ' + CLONE_EMAIL + ' ');
            Assert.areEqual(1, results.size(), 'Exactly the clone user should match its email');
            Assert.areEqual(cloneSource.Id, results[0].id);
            Assert.areEqual(STANDARD_PROFILE, results[0].profileName);
            Assert.areEqual(ROLE_NAME, results[0].roleName);

            // Wildcards in the term are matched literally.
            Assert.isTrue(UserOnboardingController.searchUsers('uo.clone%uotest').isEmpty(), '% must be escaped');
        }
    }

    @IsTest
    static void getCloneSourceReturnsAssignmentsAndManager() {
        grantAccess();
        User cloneSource = userByEmail(CLONE_EMAIL);
        PermissionSet permissionSet = [SELECT Id, Name FROM PermissionSet WHERE Label = :PERMISSION_SET_LABEL LIMIT 1];
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            UserOnboardingController.CloneSource source = UserOnboardingController.getCloneSource(cloneSource.Id);

            Assert.areEqual(cloneSource.Id, source.user.id);
            Assert.areEqual(cloneSource.ManagerId, source.manager.id, 'Manager should be returned');
            Assert.areEqual(1, source.permissionSets.size(), 'Profile-owned permission sets are excluded');
            Assert.areEqual(permissionSet.Id, source.permissionSets[0].id);
            Assert.areEqual(permissionSet.Name, source.permissionSets[0].apiName);
            Assert.areEqual(PERMISSION_SET_LABEL, source.permissionSets[0].label);
            Assert.isTrue(source.permissionSetGroups.isEmpty(), 'No permission set groups were assigned');

            Map<String, String> typeByLabel = new Map<String, String>();
            for (UserOnboardingController.GroupOption option : source.groups) {
                typeByLabel.put(option.label, option.type);
            }
            Assert.areEqual(2, source.groups.size(), 'Direct group and queue memberships are returned');
            Assert.areEqual('Group', typeByLabel.get(GROUP_NAME));
            Assert.areEqual('Queue', typeByLabel.get(QUEUE_NAME));

            // A user without a manager has a null manager.
            Assert.isNull(UserOnboardingController.getCloneSource(cloneSource.ManagerId).manager);

            try {
                UserOnboardingController.getCloneSource(null);
                Assert.fail('A null user id should be rejected');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('Select a user'), e.getMessage());
            }
        }
    }

    @IsTest
    static void getGroupsAndQueuesReturnsBothTypes() {
        grantAccess();
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            Map<String, String> typeByLabel = new Map<String, String>();
            for (UserOnboardingController.GroupOption option : UserOnboardingController.getGroupsAndQueues()) {
                Assert.isTrue(option.type == 'Group' || option.type == 'Queue', 'Unexpected type ' + option.type);
                typeByLabel.put(option.label, option.type);
            }
            Assert.areEqual('Group', typeByLabel.get(GROUP_NAME));
            Assert.areEqual('Queue', typeByLabel.get(QUEUE_NAME));
        }
    }

    @IsTest
    static void findUserByEmailMatchesCaseInsensitively() {
        grantAccess();
        User manager = userByEmail(MANAGER_EMAIL);
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            UserOnboardingController.UserOption found = UserOnboardingController.findUserByEmail(' ' + MANAGER_EMAIL.toUpperCase() + ' ');
            Assert.areEqual(manager.Id, found.id);
            Assert.areEqual(MANAGER_EMAIL, found.email);
            Assert.isNull(UserOnboardingController.findUserByEmail('nobody.here' + DOMAIN), 'Unknown email returns null');
            Assert.isNull(UserOnboardingController.findUserByEmail('  '), 'Blank email returns null');
        }
    }

    // ---------------------------------------------------------------------------------------------
    // createUser
    // ---------------------------------------------------------------------------------------------

    @IsTest
    static void createUserClonesProfileRoleManagerAndAccess() {
        grantAccess();
        String suffix = useSettings('.uo' + uniqueToken());
        User cloneSource = userByEmail(CLONE_EMAIL);
        Id publicGroupId = groupId(GROUP_NAME);
        Id queueId = groupId(QUEUE_NAME);
        Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Label = :PERMISSION_SET_LABEL LIMIT 1].Id;

        UserOnboardingController.OnboardingRequest request = newRequest(cloneSource.Id);
        request.email = '  Nina.Newhire@UOTest.example.com ';
        request.groupIds = new List<Id>{ publicGroupId, queueId, publicGroupId, null };

        UserOnboardingController.OnboardingResult result;
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            Assert.isFalse(UserOnboardingController.getAccessInfo().sendWelcomeEmail, 'Welcome email is off in tests');
            Test.startTest();
            result = UserOnboardingController.createUser(request);
            Test.stopTest();
        }

        Assert.areEqual(NEW_EMAIL + suffix, result.username, 'Username = lower-cased email + suffix');
        Assert.areEqual('Nina Newhire', result.name);
        Assert.areEqual(1, result.permissionSetsAssigned);
        Assert.areEqual(0, result.permissionSetGroupsAssigned);
        Assert.areEqual(2, result.groupsAssigned, 'Duplicate and null group ids are ignored');
        Assert.isTrue(result.warnings.isEmpty(), 'Unexpected warnings: ' + result.warnings);

        String userFields = String.join(UserOnboardingController.copyableFields(), ', ');
        String soql = 'SELECT Id, Username, Email, Alias, Title, ManagerId, CommunityNickname, ' + userFields + ' FROM User WHERE Id IN :ids';
        Set<Id> ids = new Set<Id>{ result.userId, cloneSource.Id };
        Map<Id, User> usersById = new Map<Id, User>((List<User>) Database.query(soql));
        User created = usersById.get(result.userId);
        User original = usersById.get(cloneSource.Id);

        Assert.areEqual(result.username, created.Username);
        Assert.areEqual('nina.newhire' + DOMAIN, created.Email.toLowerCase());
        Assert.areEqual('NNewhire', created.Alias);
        Assert.isTrue(created.CommunityNickname.startsWith('Nina.Newhire'), created.CommunityNickname);
        Assert.areEqual(original.ManagerId, created.ManagerId, 'Clone user manager is used by default');
        Assert.areEqual([SELECT Name FROM User WHERE Id = :original.ManagerId].Name, result.managerName);
        Assert.isNull(created.Title, 'Title must not be copied');
        for (String field : UserOnboardingController.copyableFields()) {
            Assert.areEqual(original.get(field), created.get(field), field + ' should be copied from the clone user');
        }
        Assert.areEqual(1, [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :result.userId AND PermissionSetId = :permissionSetId]);
        Set<Id> expectedGroupIds = new Set<Id>{ publicGroupId, queueId };
        Assert.areEqual(2, [SELECT COUNT() FROM GroupMember WHERE UserOrGroupId = :result.userId AND GroupId IN :expectedGroupIds]);
    }

    @IsTest
    static void createUserSendsPasswordResetAndVerificationEmails() {
        grantAccess();
        UserOnboardingController.settingOverride = new User_Onboarding_Setting__mdt(
            Username_Suffix__c = '.uo' + uniqueToken(),
            Send_Password_Reset_Email__c = true, Send_Verification_Email__c = true, Is_Active__c = true
        );
        User cloneSource = userByEmail(CLONE_EMAIL);

        UserOnboardingController.OnboardingResult result;
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            Test.startTest();
            result = UserOnboardingController.createUser(newRequest(cloneSource.Id));
            Test.stopTest();
        }

        Assert.isNotNull(result.userId, 'Email problems must never block the user from being created');
        // Each email is either sent or reported; neither path may be silent.
        Set<String> emailWarnings = new Set<String>();
        for (String warning : result.warnings) {
            emailWarnings.add(warning.substringBefore(':'));
        }
        Assert.isTrue(result.passwordResetEmailSent || emailWarnings.contains('Password reset email'), String.valueOf(result.warnings));
        Assert.isTrue(result.verificationEmailSent || emailWarnings.contains('Verification email'), String.valueOf(result.warnings));
    }

    @IsTest
    static void createUserUsesManagerOverrideAndWarnsAboutUnknownGroups() {
        grantAccess();
        useSettings('.uo' + uniqueToken());
        User admin = userByEmail(ADMIN_EMAIL);
        User otherManager = userByEmail(OTHER_MANAGER_EMAIL);
        UserOnboardingController.OnboardingRequest request = newRequest(userByEmail(CLONE_EMAIL).Id);
        request.managerEmail = OTHER_MANAGER_EMAIL.toUpperCase();
        request.groupIds = new List<Id>{ admin.Id }; // not a group or queue

        UserOnboardingController.OnboardingResult result;
        System.runAs(admin) {
            Test.startTest();
            result = UserOnboardingController.createUser(request);
            Test.stopTest();
        }

        Assert.areEqual(otherManager.Name, result.managerName);
        Assert.areEqual(otherManager.Id, [SELECT ManagerId FROM User WHERE Id = :result.userId].ManagerId);
        Assert.areEqual(0, result.groupsAssigned);
        Assert.areEqual(1, result.warnings.size(), 'Unknown group id should produce one warning');
        Assert.isTrue(result.warnings[0].contains('not found'), result.warnings[0]);
    }

    @IsTest
    static void createUserRejectsUnknownManagerEmail() {
        grantAccess();
        useSettings('.uo' + uniqueToken());
        UserOnboardingController.OnboardingRequest request = newRequest(userByEmail(CLONE_EMAIL).Id);
        request.managerEmail = 'nobody.here' + DOMAIN;
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            try {
                UserOnboardingController.createUser(request);
                Assert.fail('An unknown manager email should be rejected');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('No active user found with manager email'), e.getMessage());
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM User WHERE Email = :NEW_EMAIL], 'No user should be created');
    }

    @IsTest
    static void createUserRejectsDuplicateUsername() {
        grantAccess();
        User cloneSource = userByEmail(CLONE_EMAIL);
        // Choose the suffix so that the new username equals the clone user's username.
        useSettings(cloneSource.Username.substring(CLONE_EMAIL.length()));
        UserOnboardingController.OnboardingRequest request = newRequest(cloneSource.Id);
        request.email = CLONE_EMAIL;
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            try {
                UserOnboardingController.createUser(request);
                Assert.fail('A duplicate username should be rejected');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('already exists'), e.getMessage());
            }
        }
    }

    @IsTest
    static void createUserValidatesInput() {
        grantAccess();
        useSettings('.uo' + uniqueToken());
        Id cloneId = userByEmail(CLONE_EMAIL).Id;
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            UserOnboardingController.OnboardingRequest missingNames = newRequest(cloneId);
            missingNames.firstName = ' ';
            missingNames.lastName = null;
            assertCreateFails(missingNames, 'Missing required fields: first name, last name');

            UserOnboardingController.OnboardingRequest badEmail = newRequest(cloneId);
            badEmail.email = 'not-an-email';
            assertCreateFails(badEmail, 'valid email');

            UserOnboardingController.OnboardingRequest noClone = newRequest(null);
            assertCreateFails(noClone, 'user to clone');

            UserOnboardingController.OnboardingRequest unknownClone = newRequest(groupId(GROUP_NAME));
            assertCreateFails(unknownClone, 'not found or is inactive');

            assertCreateFails(null, 'request is empty');
        }
    }

    @IsTest
    static void insertPartialCollectsWarnings() {
        Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Label = :PERMISSION_SET_LABEL LIMIT 1].Id;
        List<SObject> records = new List<SObject>{
            new PermissionSetAssignment(AssigneeId = userByEmail(CLONE_EMAIL).Id, PermissionSetId = permissionSetId), // duplicate
            new PermissionSetAssignment(AssigneeId = userByEmail(MANAGER_EMAIL).Id, PermissionSetId = permissionSetId)
        };
        List<String> warnings = new List<String>();
        Integer successes;
        System.runAs(userByEmail(ADMIN_EMAIL)) {
            successes = UserOnboardingController.insertPartial(records, new List<String>{ 'Permission set A', 'Permission set B' }, warnings);
        }
        Assert.areEqual(1, successes, 'The valid row should still be inserted');
        Assert.areEqual(1, warnings.size());
        Assert.isTrue(warnings[0].startsWith('Permission set A: '), warnings[0]);
    }

    // ---------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------

    private static void assertCreateFails(UserOnboardingController.OnboardingRequest request, String expected) {
        try {
            UserOnboardingController.createUser(request);
            Assert.fail('Expected an error containing: ' + expected);
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains(expected), 'Got: ' + e.getMessage());
        }
    }

    private static User_Onboarding_Access__mdt rule(String accessType, String value, Boolean canCreate, Boolean active) {
        return new User_Onboarding_Access__mdt(
            Access_Type__c = accessType,
            Access_Value__c = value,
            Can_Create__c = canCreate,
            Is_Active__c = active
        );
    }

    /** Grants access, and fakes free licences: tests can exceed the org's licences but see the real counts. */
    private static void grantAccess() {
        UserOnboardingController.userLicenseAvailableOverride = 10;
        UserOnboardingController.accessRulesOverride = new List<User_Onboarding_Access__mdt>{
            rule('Profile', ADMIN_PROFILE, true, true)
        };
    }

    /** Active settings with the given suffix and all onboarding emails turned off. */
    private static String useSettings(String suffix) {
        UserOnboardingController.settingOverride = new User_Onboarding_Setting__mdt(
            Username_Suffix__c = suffix, Send_Welcome_Email__c = false, Is_Active__c = true
        );
        return suffix;
    }

    private static UserOnboardingController.OnboardingRequest newRequest(Id cloneUserId) {
        UserOnboardingController.OnboardingRequest request = new UserOnboardingController.OnboardingRequest();
        request.cloneUserId = cloneUserId;
        request.firstName = 'Nina';
        request.lastName = 'Newhire';
        request.email = NEW_EMAIL;
        request.groupIds = new List<Id>();
        return request;
    }

    private static User userByEmail(String email) {
        return [SELECT Id, Name, Username, ManagerId FROM User WHERE Email = :email ORDER BY CreatedDate DESC LIMIT 1];
    }

    private static Id groupId(String name) {
        return [SELECT Id FROM Group WHERE Name = :name AND Type IN ('Regular', 'Queue') LIMIT 1].Id;
    }

    private static String uniqueToken() {
        return String.valueOf(System.currentTimeMillis()) + String.valueOf(Math.floor(Math.random() * 100000).intValue());
    }

    /** Test user with a globally unique username; UserPermissions* flags are off to avoid feature licence limits. */
    private static User buildUser(Id profileId, String lastName, String email, String token) {
        User u = new User(
            ProfileId = profileId,
            FirstName = 'Test',
            LastName = lastName,
            Email = email,
            Username = email + '.uo' + token,
            Alias = lastName.left(8),
            CommunityNickname = (lastName + token).left(40),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        for (Schema.SObjectField field : User.SObjectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (describe.getName().startsWith('UserPermissions')
                    && describe.getType() == Schema.DisplayType.BOOLEAN
                    && describe.isCreateable()) {
                u.put(field, false);
            }
        }
        return u;
    }
}
