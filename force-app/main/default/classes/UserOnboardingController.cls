/**
 * Server side of the User Onboarding utility: lets authorised admins create a new user by
 * cloning an existing one (profile, role, manager, permission sets, licences, groups and queues).
 *
 * Authorisation comes from User_Onboarding_Access__mdt and is enforced in every method. Creation is
 * all-or-nothing up to the user insert: if anything throws, the transaction rolls back and no user
 * exists. After the insert, individual assignments and emails succeed or fail on their own.
 * Data access modes are chosen deliberately:
 *  - SYSTEM_MODE for resolving the running user's own access and for org-wide uniqueness checks
 *    (username, community nickname), which must see every user regardless of sharing.
 *  - USER_MODE for everything the user browses or creates, so the platform's own permissions
 *    (View Setup, Manage Users, Assign Permission Sets) still apply on top of the metadata gate.
 */
public with sharing class UserOnboardingController {
    private static final String ACCESS_USERNAME = 'Username';
    private static final String ACCESS_PROFILE = 'Profile';
    private static final String ACCESS_PERMISSION_SET = 'Permission Set';
    private static final String DEFAULT_SETTING = 'Default';

    private static final String NO_ACCESS_MESSAGE = 'You do not have access to the User Onboarding tool.';

    /** Platform permissions the tool needs, since it runs in user mode. Field on UserPermissionAccess => label. */
    private static final Map<String, String> REQUIRED_PERMISSIONS = new Map<String, String>{
        'PermissionsViewSetup' => 'View Setup and Configuration',
        'PermissionsManageUsers' => 'Manage Users',
        'PermissionsAssignPermissionSets' => 'Assign Permission Sets'
    };

    private static final List<String> GROUP_TYPES = new List<String>{ 'Regular', 'Queue' };
    private static final Integer MIN_SEARCH_LENGTH = 2;
    private static final Integer SEARCH_LIMIT = 15;
    private static final Integer GROUP_LIMIT = 2000;
    private static final String EMAIL_PATTERN = '^[A-Za-z0-9._%+\'-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}$';

    /** User fields copied from the clone user when they exist and are createable in this org. */
    private static final List<String> CLONED_FIELDS = new List<String>{
        'ProfileId', 'UserRoleId', 'TimeZoneSidKey', 'LocaleSidKey', 'EmailEncodingKey', 'LanguageLocaleKey',
        'CompanyName', 'Department', 'Division', 'Country', 'Street', 'City', 'State', 'PostalCode'
    };

    /** Test hooks: custom metadata cannot be inserted in tests, so tests inject in-memory records. */
    @TestVisible
    static List<User_Onboarding_Access__mdt> accessRulesOverride;
    @TestVisible
    static User_Onboarding_Setting__mdt settingOverride;
    /** Test hooks: admins running tests have every permission and licence counts can't be changed. */
    @TestVisible
    static Set<String> missingPermissionOverride = new Set<String>();
    @TestVisible
    static Integer userLicenseAvailableOverride;

    private static List<String> copyableFieldCache;

    // ---------------------------------------------------------------------------------------------
    // DTOs
    // ---------------------------------------------------------------------------------------------

    public class AccessInfo {
        /** True when an active access rule matches the running user. */
        @AuraEnabled public Boolean canCreate { get; set; }
        /** Labels of required platform permissions the running user lacks; the tool is unusable until empty. */
        @AuraEnabled public List<String> missingPermissions { get; set; }
        @AuraEnabled public String usernameSuffix { get; set; }
        @AuraEnabled public Boolean sendWelcomeEmail { get; set; }
        @AuraEnabled public Boolean sendPasswordResetEmail { get; set; }
        @AuraEnabled public Boolean sendVerificationEmail { get; set; }

        public AccessInfo() {
            canCreate = false;
            missingPermissions = new List<String>();
            usernameSuffix = '';
            sendWelcomeEmail = false;
            sendPasswordResetEmail = true;
            sendVerificationEmail = true;
        }
    }

    public class UserOption {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String username { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String profileName { get; set; }
        @AuraEnabled public String roleName { get; set; }
        @AuraEnabled public String smallPhotoUrl { get; set; }

        public UserOption(User u) {
            id = u.Id;
            name = u.Name;
            username = u.Username;
            email = u.Email;
            title = u.Title;
            profileName = u.Profile?.Name;
            roleName = u.UserRole?.Name;
            smallPhotoUrl = u.SmallPhotoUrl;
        }
    }

    public class NamedItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String apiName { get; set; }

        public NamedItem(Id recordId, String itemLabel, String itemApiName) {
            id = recordId;
            label = itemLabel;
            apiName = itemApiName;
        }
    }

    public class GroupOption {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String developerName { get; set; }
        /** 'Group' for public (Regular) groups, 'Queue' for queues. */
        @AuraEnabled public String type { get; set; }

        public GroupOption(Group g) {
            id = g.Id;
            label = String.isBlank(g.Name) ? g.DeveloperName : g.Name;
            developerName = g.DeveloperName;
            type = g.Type == 'Queue' ? 'Queue' : 'Group';
        }
    }

    public class CloneSource {
        @AuraEnabled public UserOption user { get; set; }
        @AuraEnabled public UserOption manager { get; set; }
        @AuraEnabled public List<NamedItem> permissionSets { get; set; }
        @AuraEnabled public List<NamedItem> permissionSetGroups { get; set; }
        @AuraEnabled public List<NamedItem> permissionSetLicenses { get; set; }
        @AuraEnabled public List<GroupOption> groups { get; set; }
        /** The Salesforce user licence the clone user's profile consumes, and how many are left. */
        @AuraEnabled public String userLicenseName { get; set; }
        @AuraEnabled public Integer userLicensesAvailable { get; set; }
        /** Labels of the clone user's permission set licences that have none left to assign. */
        @AuraEnabled public List<String> exhaustedPermissionSetLicenses { get; set; }

        public CloneSource() {
            exhaustedPermissionSetLicenses = new List<String>();
            permissionSets = new List<NamedItem>();
            permissionSetGroups = new List<NamedItem>();
            permissionSetLicenses = new List<NamedItem>();
            groups = new List<GroupOption>();
        }
    }

    public class OnboardingRequest {
        @AuraEnabled public Id cloneUserId { get; set; }
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String managerEmail { get; set; }
        @AuraEnabled public List<Id> groupIds { get; set; }
    }

    public class OnboardingResult {
        @AuraEnabled public Id userId { get; set; }
        @AuraEnabled public String username { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String managerName { get; set; }
        @AuraEnabled public Integer permissionSetsAssigned { get; set; }
        @AuraEnabled public Integer permissionSetGroupsAssigned { get; set; }
        @AuraEnabled public Integer licensesAssigned { get; set; }
        @AuraEnabled public Integer groupsAssigned { get; set; }
        @AuraEnabled public Boolean passwordResetEmailSent { get; set; }
        @AuraEnabled public Boolean verificationEmailSent { get; set; }
        @AuraEnabled public List<String> warnings { get; set; }

        public OnboardingResult() {
            passwordResetEmailSent = false;
            verificationEmailSent = false;
            permissionSetsAssigned = 0;
            permissionSetGroupsAssigned = 0;
            licensesAssigned = 0;
            groupsAssigned = 0;
            warnings = new List<String>();
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Aura-enabled API
    // ---------------------------------------------------------------------------------------------

    /** Access flags and settings for the running user. Missing access is reported, not thrown. */
    @AuraEnabled(cacheable=true)
    public static AccessInfo getAccessInfo() {
        try {
            return resolveAccess();
        } catch (Exception e) {
            throw asAuraException(e);
        }
    }

    /** Active standard users whose name, username or email contains the (trimmed) term. */
    @AuraEnabled(cacheable=true)
    public static List<UserOption> searchUsers(String searchTerm) {
        try {
            requireAccess();
            List<UserOption> options = new List<UserOption>();
            String term = searchTerm == null ? '' : searchTerm.trim();
            if (term.length() < MIN_SEARCH_LENGTH) {
                return options;
            }
            String likePattern = '%' + escapeLike(term) + '%';
            for (User u : [
                SELECT Id, Name, Username, Email, Title, Profile.Name, UserRole.Name, SmallPhotoUrl
                FROM User
                WHERE IsActive = TRUE AND UserType = 'Standard'
                    AND (Name LIKE :likePattern OR Username LIKE :likePattern OR Email LIKE :likePattern)
                WITH USER_MODE
                ORDER BY Name
                LIMIT :SEARCH_LIMIT
            ]) {
                options.add(new UserOption(u));
            }
            return options;
        } catch (Exception e) {
            throw asAuraException(e);
        }
    }

    /** Everything the UI shows about the user being cloned. */
    @AuraEnabled(cacheable=true)
    public static CloneSource getCloneSource(Id userId) {
        try {
            requireAccess();
            if (userId == null) {
                throw error('Select a user to clone.');
            }
            List<User> users = [
                SELECT Id, Name, Username, Email, Title, Profile.Name, Profile.UserLicenseId, UserRole.Name, SmallPhotoUrl, ManagerId
                FROM User
                WHERE Id = :userId
                WITH USER_MODE
            ];
            if (users.isEmpty()) {
                throw error('The selected user was not found.');
            }
            CloneSource source = loadAssignments(userId, true);
            source.user = new UserOption(users[0]);
            UserLicense licence = queryUserLicense(users[0].Profile.UserLicenseId);
            if (licence != null) {
                source.userLicenseName = licence.Name;
                source.userLicensesAvailable = available(licence);
            }
            source.exhaustedPermissionSetLicenses = exhaustedPermissionSetLicenses(source.permissionSetLicenses);
            if (users[0].ManagerId != null) {
                Id managerId = users[0].ManagerId;
                for (User manager : [
                    SELECT Id, Name, Username, Email, Title, Profile.Name, UserRole.Name, SmallPhotoUrl
                    FROM User
                    WHERE Id = :managerId
                    WITH USER_MODE
                ]) {
                    source.manager = new UserOption(manager);
                }
            }
            return source;
        } catch (Exception e) {
            throw asAuraException(e);
        }
    }

    /** All public groups and queues, for the "add more groups" picker. */
    @AuraEnabled(cacheable=true)
    public static List<GroupOption> getGroupsAndQueues() {
        try {
            requireAccess();
            List<GroupOption> options = new List<GroupOption>();
            for (Group g : [
                SELECT Id, Name, DeveloperName, Type
                FROM Group
                WHERE Type IN :GROUP_TYPES
                WITH USER_MODE
                ORDER BY Name
                LIMIT :GROUP_LIMIT
            ]) {
                options.add(new GroupOption(g));
            }
            return options;
        } catch (Exception e) {
            throw asAuraException(e);
        }
    }

    /** Active standard user with this exact email (most recently created wins), or null. */
    @AuraEnabled(cacheable=true)
    public static UserOption findUserByEmail(String email) {
        try {
            requireAccess();
            User match = findActiveUserByEmail(email);
            return match == null ? null : new UserOption(match);
        } catch (Exception e) {
            throw asAuraException(e);
        }
    }

    /**
     * Creates the new user from the clone user, then copies licences, permission sets, permission
     * set groups and the requested group/queue memberships with partial success. Assignment failures
     * are reported in OnboardingResult.warnings; only validation and the user insert itself throw.
     */
    @AuraEnabled
    public static OnboardingResult createUser(OnboardingRequest request) {
        try {
            AccessInfo access = requireAccess();
            validate(request);

            String email = request.email.trim();
            String username = buildUsername(email, access.usernameSuffix);
            User cloneUser = queryCloneUser(request.cloneUserId);
            requireUserLicence(cloneUser.Profile.UserLicenseId);
            if (![SELECT Id FROM User WHERE Username = :username WITH SYSTEM_MODE LIMIT 1].isEmpty()) {
                throw error('A user with the username ' + username + ' already exists.');
            }

            Id managerId = cloneUser.ManagerId;
            String managerName = cloneUser.Manager?.Name;
            if (String.isNotBlank(request.managerEmail)) {
                User manager = findActiveUserByEmail(request.managerEmail);
                if (manager == null) {
                    throw error('No active user found with manager email ' + request.managerEmail.trim() + '.');
                }
                managerId = manager.Id;
                managerName = manager.Name;
            }

            User newUser = new User();
            for (String field : copyableFields()) {
                newUser.put(field, cloneUser.get(field));
            }
            newUser.FirstName = request.firstName.trim();
            newUser.LastName = request.lastName.trim();
            newUser.Email = email;
            newUser.Username = username;
            newUser.Alias = buildAlias(newUser.FirstName, newUser.LastName);
            newUser.CommunityNickname = uniqueNickname(email);
            newUser.ManagerId = managerId;
            insertUser(newUser, access.sendWelcomeEmail);

            OnboardingResult result = new OnboardingResult();
            result.userId = newUser.Id;
            result.username = username;
            result.name = newUser.FirstName + ' ' + newUser.LastName;
            result.managerName = managerName;
            assignAccess(newUser.Id, request.cloneUserId, request.groupIds, result);
            sendOnboardingEmails(newUser.Id, access, result);
            return result;
        } catch (Exception e) {
            throw asAuraException(e);
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Access
    // ---------------------------------------------------------------------------------------------

    /** OR of every active access rule matching the running user, plus the Default settings. */
    private static AccessInfo resolveAccess() {
        AccessInfo info = new AccessInfo();
        User_Onboarding_Setting__mdt setting = settingOverride != null
            ? settingOverride
            : User_Onboarding_Setting__mdt.getInstance(DEFAULT_SETTING);
        if (setting != null && setting.Is_Active__c == true) {
            info.usernameSuffix = String.isBlank(setting.Username_Suffix__c) ? '' : setting.Username_Suffix__c.trim();
            info.sendPasswordResetEmail = setting.Send_Password_Reset_Email__c == true;
            info.sendVerificationEmail = setting.Send_Verification_Email__c == true;
            // A password reset invalidates the welcome email's set-password link, so it replaces it.
            info.sendWelcomeEmail = setting.Send_Welcome_Email__c == true && !info.sendPasswordResetEmail;
        }

        List<User_Onboarding_Access__mdt> rules = new List<User_Onboarding_Access__mdt>();
        List<User_Onboarding_Access__mdt> candidates = accessRulesOverride != null
            ? accessRulesOverride
            : User_Onboarding_Access__mdt.getAll().values();
        for (User_Onboarding_Access__mdt rule : candidates) {
            if (rule.Is_Active__c == true && rule.Can_Create__c == true && String.isNotBlank(rule.Access_Value__c)) {
                rules.add(rule);
            }
        }
        if (rules.isEmpty()) {
            return info;
        }

        Set<String> identities = runningUserIdentities(rules);
        for (User_Onboarding_Access__mdt rule : rules) {
            if (identities.contains(accessKey(rule.Access_Type__c, rule.Access_Value__c))) {
                info.canCreate = true;
                break;
            }
        }
        if (info.canCreate) {
            info.missingPermissions = missingPlatformPermissions();
        }
        return info;
    }

    /** Required platform permissions the running user lacks (UserPermissionAccess reflects only the running user). */
    private static List<String> missingPlatformPermissions() {
        List<String> missing = new List<String>();
        String soql = 'SELECT ' + String.join(new List<String>(REQUIRED_PERMISSIONS.keySet()), ', ') + ' FROM UserPermissionAccess LIMIT 1';
        List<SObject> rows = Database.query(soql, AccessLevel.SYSTEM_MODE);
        for (String field : REQUIRED_PERMISSIONS.keySet()) {
            if (rows.isEmpty() || rows[0].get(field) != true || missingPermissionOverride.contains(field)) {
                missing.add(REQUIRED_PERMISSIONS.get(field));
            }
        }
        return missing;
    }

    /** "Type:value" keys describing the running user; only queries what the rules need. */
    private static Set<String> runningUserIdentities(List<User_Onboarding_Access__mdt> rules) {
        Set<String> ruleTypes = new Set<String>();
        for (User_Onboarding_Access__mdt rule : rules) {
            ruleTypes.add(rule.Access_Type__c);
        }

        Set<String> identities = new Set<String>{ accessKey(ACCESS_USERNAME, UserInfo.getUserName()) };
        if (ruleTypes.contains(ACCESS_PROFILE)) {
            Id profileId = UserInfo.getProfileId();
            for (Profile p : [SELECT Name FROM Profile WHERE Id = :profileId WITH SYSTEM_MODE]) {
                identities.add(accessKey(ACCESS_PROFILE, p.Name));
            }
        }
        if (ruleTypes.contains(ACCESS_PERMISSION_SET)) {
            Id userId = UserInfo.getUserId();
            Set<Id> permissionSetGroupIds = new Set<Id>();
            for (PermissionSetAssignment psa : [
                SELECT PermissionSet.Name, PermissionSetGroupId, PermissionSetGroup.DeveloperName
                FROM PermissionSetAssignment
                WHERE AssigneeId = :userId
                WITH SYSTEM_MODE
            ]) {
                if (psa.PermissionSetGroupId != null) {
                    permissionSetGroupIds.add(psa.PermissionSetGroupId);
                    identities.add(accessKey(ACCESS_PERMISSION_SET, psa.PermissionSetGroup.DeveloperName));
                } else {
                    identities.add(accessKey(ACCESS_PERMISSION_SET, psa.PermissionSet.Name));
                }
            }
            if (!permissionSetGroupIds.isEmpty()) {
                for (PermissionSetGroupComponent component : [
                    SELECT PermissionSet.Name
                    FROM PermissionSetGroupComponent
                    WHERE PermissionSetGroupId IN :permissionSetGroupIds
                    WITH SYSTEM_MODE
                ]) {
                    identities.add(accessKey(ACCESS_PERMISSION_SET, component.PermissionSet.Name));
                }
            }
        }
        return identities;
    }

    private static String accessKey(String accessType, String value) {
        return accessType + ':' + (value == null ? '' : value.trim().toLowerCase());
    }

    private static AccessInfo requireAccess() {
        AccessInfo access = resolveAccess();
        if (!access.canCreate) {
            throw error(NO_ACCESS_MESSAGE);
        }
        if (!access.missingPermissions.isEmpty()) {
            throw error(missingPermissionsMessage(access.missingPermissions));
        }
        return access;
    }

    @TestVisible
    private static String missingPermissionsMessage(List<String> missing) {
        return 'Your user is missing permissions the User Onboarding tool needs: ' + String.join(missing, ', ')
            + '. Ask a Salesforce administrator to grant them.';
    }

    // ---------------------------------------------------------------------------------------------
    // Licences
    // ---------------------------------------------------------------------------------------------

    private static UserLicense queryUserLicense(Id userLicenseId) {
        if (userLicenseId == null) {
            return null;
        }
        List<UserLicense> licences = [
            SELECT Name, TotalLicenses, UsedLicenses FROM UserLicense WHERE Id = :userLicenseId WITH SYSTEM_MODE
        ];
        return licences.isEmpty() ? null : licences[0];
    }

    private static Integer available(UserLicense licence) {
        return userLicenseAvailableOverride != null
            ? userLicenseAvailableOverride
            : licence.TotalLicenses - licence.UsedLicenses;
    }

    /** Fails fast, before anything is created, when the clone user's licence type has none left. */
    private static void requireUserLicence(Id userLicenseId) {
        UserLicense licence = queryUserLicense(userLicenseId);
        if (licence != null && available(licence) <= 0) {
            throw error(noLicenceMessage(licence.Name, licence.TotalLicenses));
        }
    }

    private static String noLicenceMessage(String licenceName, Integer total) {
        return 'No ' + licenceName + ' licences are left (all ' + total + ' are in use). '
            + 'Deactivate a user who no longer needs one, buy more licences, or clone a user with a different licence type.';
    }

    private static List<String> exhaustedPermissionSetLicenses(List<NamedItem> licences) {
        Set<Id> licenceIds = new Set<Id>();
        for (NamedItem item : licences) {
            licenceIds.add(item.id);
        }
        List<String> exhausted = new List<String>();
        for (PermissionSetLicense licence : [
            SELECT MasterLabel, TotalLicenses, UsedLicenses FROM PermissionSetLicense WHERE Id IN :licenceIds WITH SYSTEM_MODE
        ]) {
            if (licence.TotalLicenses - licence.UsedLicenses <= 0) {
                exhausted.add(licence.MasterLabel);
            }
        }
        return exhausted;
    }

    // ---------------------------------------------------------------------------------------------
    // Queries
    // ---------------------------------------------------------------------------------------------

    /** The clone user's permission sets, groups, licences and (optionally) group/queue memberships. */
    private static CloneSource loadAssignments(Id userId, Boolean includeGroups) {
        CloneSource source = new CloneSource();
        Set<Id> seenGroupIds = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT PermissionSetId, PermissionSet.Name, PermissionSet.Label, PermissionSet.IsOwnedByProfile,
                PermissionSetGroupId, PermissionSetGroup.DeveloperName, PermissionSetGroup.MasterLabel
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
            WITH USER_MODE
            ORDER BY PermissionSet.Label
        ]) {
            if (psa.PermissionSetGroupId != null) {
                if (seenGroupIds.add(psa.PermissionSetGroupId)) {
                    source.permissionSetGroups.add(new NamedItem(
                        psa.PermissionSetGroupId, psa.PermissionSetGroup.MasterLabel, psa.PermissionSetGroup.DeveloperName
                    ));
                }
            } else if (!psa.PermissionSet.IsOwnedByProfile) {
                source.permissionSets.add(new NamedItem(psa.PermissionSetId, psa.PermissionSet.Label, psa.PermissionSet.Name));
            }
        }

        for (PermissionSetLicenseAssign licence : [
            SELECT PermissionSetLicenseId, PermissionSetLicense.MasterLabel, PermissionSetLicense.DeveloperName
            FROM PermissionSetLicenseAssign
            WHERE AssigneeId = :userId
            WITH USER_MODE
            ORDER BY PermissionSetLicense.MasterLabel
        ]) {
            source.permissionSetLicenses.add(new NamedItem(
                licence.PermissionSetLicenseId, licence.PermissionSetLicense.MasterLabel, licence.PermissionSetLicense.DeveloperName
            ));
        }

        if (includeGroups) {
            for (GroupMember member : [
                SELECT GroupId, Group.Name, Group.DeveloperName, Group.Type
                FROM GroupMember
                WHERE UserOrGroupId = :userId AND Group.Type IN :GROUP_TYPES
                WITH USER_MODE
                ORDER BY Group.Name
            ]) {
                source.groups.add(new GroupOption(member.Group));
            }
        }
        return source;
    }

    private static User findActiveUserByEmail(String email) {
        if (String.isBlank(email)) {
            return null;
        }
        String normalized = email.trim();
        List<User> users = [
            SELECT Id, Name, Username, Email, Title, Profile.Name, UserRole.Name, SmallPhotoUrl
            FROM User
            WHERE Email = :normalized AND IsActive = TRUE AND UserType = 'Standard'
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }

    /** Clone user with every copyable field; queried dynamically so org-specific fields are optional. */
    private static User queryCloneUser(Id cloneUserId) {
        List<String> fields = new List<String>{ 'Id', 'IsActive', 'ManagerId', 'Manager.Name', 'Profile.UserLicenseId' };
        fields.addAll(copyableFields());
        String soql = 'SELECT ' + String.join(fields, ', ') + ' FROM User WHERE Id = :cloneUserId';
        List<User> users = Database.queryWithBinds(
            soql, new Map<String, Object>{ 'cloneUserId' => cloneUserId }, AccessLevel.USER_MODE
        );
        if (users.isEmpty() || !users[0].IsActive) {
            throw error('The user to clone was not found or is inactive.');
        }
        return users[0];
    }

    /** CLONED_FIELDS plus every createable Boolean UserPermissions* field on User in this org. */
    @TestVisible
    private static List<String> copyableFields() {
        if (copyableFieldCache != null) {
            return copyableFieldCache;
        }
        Map<String, Schema.SObjectField> fieldMap = User.SObjectType.getDescribe().fields.getMap();
        copyableFieldCache = new List<String>();
        for (String fieldName : CLONED_FIELDS) {
            Schema.SObjectField field = fieldMap.get(fieldName.toLowerCase());
            if (field != null && field.getDescribe().isCreateable()) {
                copyableFieldCache.add(field.getDescribe().getName());
            }
        }
        for (Schema.SObjectField field : fieldMap.values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (describe.getName().startsWith('UserPermissions')
                    && describe.getType() == Schema.DisplayType.BOOLEAN
                    && describe.isCreateable()) {
                copyableFieldCache.add(describe.getName());
            }
        }
        return copyableFieldCache;
    }

    // ---------------------------------------------------------------------------------------------
    // Creation helpers
    // ---------------------------------------------------------------------------------------------

    private static void validate(OnboardingRequest request) {
        if (request == null) {
            throw error('The onboarding request is empty.');
        }
        List<String> missing = new List<String>();
        if (request.cloneUserId == null) {
            missing.add('user to clone');
        }
        if (String.isBlank(request.firstName)) {
            missing.add('first name');
        }
        if (String.isBlank(request.lastName)) {
            missing.add('last name');
        }
        if (String.isBlank(request.email)) {
            missing.add('email');
        }
        if (!missing.isEmpty()) {
            throw error('Missing required fields: ' + String.join(missing, ', ') + '.');
        }
        if (!Pattern.matches(EMAIL_PATTERN, request.email.trim())) {
            throw error('Enter a valid email address.');
        }
    }

    /** The username rule shared with the LWC preview. */
    @TestVisible
    private static String buildUsername(String email, String suffix) {
        return email.trim().toLowerCase() + (suffix == null ? '' : suffix.trim());
    }

    /** First letter of the first name plus the last name, letters and digits only, max 8 chars. */
    @TestVisible
    private static String buildAlias(String firstName, String lastName) {
        String alias = (firstName.left(1) + lastName).replaceAll('[^A-Za-z0-9]', '').left(8);
        return String.isBlank(alias) ? 'newuser' : alias;
    }

    /** Email local part plus 4 random digits, checked against existing nicknames in one query. */
    private static String uniqueNickname(String email) {
        String base = email.substringBefore('@').left(36);
        List<String> candidates = new List<String>();
        for (Integer i = 0; i < 5; i++) {
            candidates.add(base + String.valueOf(1000 + Math.floor(Math.random() * 9000).intValue()));
        }
        Set<String> taken = new Set<String>();
        for (User u : [SELECT CommunityNickname FROM User WHERE CommunityNickname IN :candidates WITH SYSTEM_MODE]) {
            taken.add(u.CommunityNickname.toLowerCase());
        }
        for (String candidate : candidates) {
            if (!taken.contains(candidate.toLowerCase())) {
                return candidate;
            }
        }
        return (base.left(27) + String.valueOf(System.currentTimeMillis())).left(40);
    }

    private static void insertUser(User newUser, Boolean sendWelcomeEmail) {
        Database.DMLOptions options = new Database.DMLOptions();
        options.EmailHeader.triggerUserEmail = sendWelcomeEmail;
        options.OptAllOrNone = false;
        Database.SaveResult saveResult;
        try {
            saveResult = Database.insert(newUser, options, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw error('The user could not be created: ' + e.getMessage());
        }
        if (!saveResult.isSuccess()) {
            for (Database.Error err : saveResult.getErrors()) {
                if (err.getStatusCode() == StatusCode.LICENSE_LIMIT_EXCEEDED) {
                    throw error('The user could not be created because no licences are left for this profile. '
                        + 'Deactivate a user who no longer needs one, or buy more licences.');
                }
                if (err.getStatusCode() == StatusCode.DUPLICATE_USERNAME) {
                    throw error('The username ' + newUser.Username + ' is already used in another Salesforce org. '
                        + 'Usernames are unique across all orgs; set a Username Suffix in User Onboarding Setting.');
                }
            }
            throw error('The user could not be created: ' + joinErrors(saveResult.getErrors()));
        }
    }

    /**
     * Sends the password reset and email verification emails. Runs last so the user already has
     * their access; a failure here never undoes the user and is reported as a warning instead.
     */
    private static void sendOnboardingEmails(Id newUserId, AccessInfo access, OnboardingResult result) {
        if (access.sendPasswordResetEmail) {
            try {
                System.resetPassword(newUserId, true);
                result.passwordResetEmailSent = true;
            } catch (Exception e) {
                result.warnings.add('Password reset email: ' + e.getMessage());
            }
        }
        if (access.sendVerificationEmail) {
            try {
                result.verificationEmailSent = System.UserManagement.sendAsyncEmailConfirmation(newUserId, null, null, null);
                if (!result.verificationEmailSent) {
                    result.warnings.add('Verification email: Salesforce did not accept the request.');
                }
            } catch (Exception e) {
                result.warnings.add('Verification email: ' + e.getMessage());
            }
        }
    }

    /** Copies the clone user's access to the new user. Licences first: some permission sets need them. */
    private static void assignAccess(Id newUserId, Id cloneUserId, List<Id> groupIds, OnboardingResult result) {
        CloneSource source = loadAssignments(cloneUserId, false);

        // Licences may already have been granted automatically with the user licence.
        Set<Id> existingLicences = new Set<Id>();
        for (PermissionSetLicenseAssign licence : [
            SELECT PermissionSetLicenseId FROM PermissionSetLicenseAssign WHERE AssigneeId = :newUserId WITH USER_MODE
        ]) {
            existingLicences.add(licence.PermissionSetLicenseId);
        }
        List<SObject> records = new List<SObject>();
        List<String> labels = new List<String>();
        for (NamedItem item : source.permissionSetLicenses) {
            if (!existingLicences.contains(item.id)) {
                records.add(new PermissionSetLicenseAssign(AssigneeId = newUserId, PermissionSetLicenseId = item.id));
                labels.add('Permission set license ' + item.label);
            }
        }
        result.licensesAssigned = insertPartial(records, labels, result.warnings);

        records = new List<SObject>();
        labels = new List<String>();
        for (NamedItem item : source.permissionSets) {
            records.add(new PermissionSetAssignment(AssigneeId = newUserId, PermissionSetId = item.id));
            labels.add('Permission set ' + item.label);
        }
        result.permissionSetsAssigned = insertPartial(records, labels, result.warnings);

        records = new List<SObject>();
        labels = new List<String>();
        for (NamedItem item : source.permissionSetGroups) {
            records.add(new PermissionSetAssignment(AssigneeId = newUserId, PermissionSetGroupId = item.id));
            labels.add('Permission set group ' + item.label);
        }
        result.permissionSetGroupsAssigned = insertPartial(records, labels, result.warnings);

        Set<Id> requestedGroupIds = new Set<Id>();
        if (groupIds != null) {
            requestedGroupIds.addAll(groupIds);
            requestedGroupIds.remove(null);
        }
        Map<Id, Group> groupsById = new Map<Id, Group>([
            SELECT Id, Name, DeveloperName, Type FROM Group WHERE Id IN :requestedGroupIds AND Type IN :GROUP_TYPES WITH USER_MODE
        ]);
        records = new List<SObject>();
        labels = new List<String>();
        for (Id groupId : requestedGroupIds) {
            Group g = groupsById.get(groupId);
            if (g == null) {
                result.warnings.add('Group or queue ' + groupId + ': not found.');
                continue;
            }
            GroupOption option = new GroupOption(g);
            records.add(new GroupMember(GroupId = groupId, UserOrGroupId = newUserId));
            labels.add(option.type + ' ' + option.label);
        }
        result.groupsAssigned = insertPartial(records, labels, result.warnings);
    }

    /** Partial-success insert; returns the number of successes and adds "label: error" warnings. */
    @TestVisible
    private static Integer insertPartial(List<SObject> records, List<String> labels, List<String> warnings) {
        if (records.isEmpty()) {
            return 0;
        }
        List<Database.SaveResult> saveResults;
        try {
            saveResults = Database.insert(records, false, AccessLevel.USER_MODE);
        } catch (Exception e) {
            for (String label : labels) {
                warnings.add(label + ': ' + e.getMessage());
            }
            return 0;
        }
        Integer successes = 0;
        for (Integer i = 0; i < saveResults.size(); i++) {
            if (saveResults[i].isSuccess()) {
                successes++;
            } else {
                warnings.add(labels[i] + ': ' + joinErrors(saveResults[i].getErrors()));
            }
        }
        return successes;
    }

    private static String joinErrors(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error err : errors) {
            messages.add(err.getMessage());
        }
        return String.join(messages, '; ');
    }

    /** Escapes LIKE wildcards so the term is matched literally (the value is always bound, never concatenated). */
    @TestVisible
    private static String escapeLike(String value) {
        return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    private static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    private static AuraHandledException asAuraException(Exception e) {
        return e instanceof AuraHandledException ? (AuraHandledException) e : error(e.getMessage());
    }
}
