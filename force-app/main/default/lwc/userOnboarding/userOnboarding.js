import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAccessInfo from '@salesforce/apex/UserOnboardingController.getAccessInfo';
import searchUsers from '@salesforce/apex/UserOnboardingController.searchUsers';
import getCloneSource from '@salesforce/apex/UserOnboardingController.getCloneSource';
import getGroupsAndQueues from '@salesforce/apex/UserOnboardingController.getGroupsAndQueues';
import findUserByEmail from '@salesforce/apex/UserOnboardingController.findUserByEmail';
import createUser from '@salesforce/apex/UserOnboardingController.createUser';

const STEPS = [
    { value: 1, label: 'Clone from' },
    { value: 2, label: 'New user' },
    { value: 3, label: 'Extras' },
    { value: 4, label: 'Review' }
];
const STEP_TITLES = {
    1: 'Clone from',
    2: 'New user',
    3: 'Extras',
    4: 'Review and create'
};
const LAST_STEP = STEPS.length;
const SEARCH_DEBOUNCE_MS = 300;
const MIN_SEARCH_LENGTH = 2;
const MAX_GROUP_MATCHES = 50;
const LOW_LICENCE_THRESHOLD = 3;
const EDITABLE_FIELDS = ['firstName', 'lastName', 'email'];

/**
 * Flattens the many shapes Salesforce errors come in (AuraHandledException,
 * page/field errors, arrays, plain Errors, strings) into one readable string.
 */
function reduceErrors(errors) {
    const list = Array.isArray(errors) ? errors : [errors];
    const messages = [];
    list.filter(Boolean).forEach((error) => {
        if (typeof error === 'string') {
            messages.push(error);
        } else if (Array.isArray(error.body)) {
            error.body.forEach((item) => messages.push(item && item.message));
        } else if (error.body && typeof error.body.message === 'string' && error.body.message) {
            messages.push(error.body.message);
        } else if (error.body && Array.isArray(error.body.pageErrors) && error.body.pageErrors.length) {
            error.body.pageErrors.forEach((item) => messages.push(item && item.message));
        } else if (error.body && error.body.fieldErrors) {
            Object.values(error.body.fieldErrors).forEach((fieldList) => {
                (fieldList || []).forEach((item) => messages.push(item && item.message));
            });
        } else if (typeof error.message === 'string' && error.message) {
            messages.push(error.message);
        } else if (error.statusText) {
            messages.push(error.statusText);
        }
    });
    const clean = messages.filter(Boolean);
    return clean.length ? clean.join(' ') : 'An unexpected error occurred. Please try again.';
}

function getInitials(name) {
    const parts = String(name || '')
        .trim()
        .split(/\s+/)
        .filter(Boolean);
    if (!parts.length) {
        return '?';
    }
    const first = parts[0].charAt(0);
    const last = parts.length > 1 ? parts[parts.length - 1].charAt(0) : '';
    return `${first}${last}`.toUpperCase();
}

function toUserView(user) {
    return {
        id: user.id,
        name: user.name,
        username: user.username,
        email: user.email,
        title: user.title,
        profileName: user.profileName,
        roleName: user.roleName,
        smallPhotoUrl: user.smallPhotoUrl,
        initials: getInitials(user.name),
        metaLine: [user.profileName, user.roleName].filter(Boolean).join(' · ')
    };
}

function toNamedItems(items) {
    return (items || []).map((item) => ({ id: item.id, label: item.label || item.apiName }));
}

function pluralize(count, singular, plural) {
    return `${count} ${count === 1 ? singular : plural}`;
}

export default class UserOnboarding extends NavigationMixin(LightningElement) {
    steps = STEPS;
    step = 1;
    direction = 'forward';
    liveMessage = '';

    // Access
    isLoadingAccess = true;
    accessError = '';
    canCreate = false;
    missingPermissions = [];
    usernameSuffix = '';
    sendWelcomeEmail = false;
    sendPasswordResetEmail = true;
    sendVerificationEmail = true;

    // Step 1: search and clone source
    searchTerm = '';
    isSearching = false;
    hasSearched = false;
    searchError = '';
    searchResults = [];
    selectedUser = null;
    cloneUser = null;
    cloneSource = null;
    cloneDetails = null;
    isLoadingClone = false;
    cloneError = '';

    // Step 2: new user
    firstName = '';
    lastName = '';
    email = '';

    // Step 3: manager, groups and queues
    managerEmail = '';
    managerStatus = '';
    manager = null;
    managerError = '';
    allGroups = [];
    groupsLoaded = false;
    isLoadingGroups = false;
    groupsError = '';
    selectedGroups = [];
    groupFilter = '';
    availableGroupItems = [];
    groupMatchTotal = 0;

    // Step 4 and result
    isCreating = false;
    createError = '';
    isSuccess = false;
    result = null;

    searchTimer;
    searchRequestId = 0;
    managerLookupKey = '';
    focusPanelPending = false;

    connectedCallback() {
        this.loadAccess();
    }

    disconnectedCallback() {
        window.clearTimeout(this.searchTimer);
    }

    renderedCallback() {
        if (this.focusPanelPending) {
            const target = this.template.querySelector('[data-focus-target]');
            if (target) {
                this.focusPanelPending = false;
                target.focus({ preventScroll: false });
            }
        }
    }

    // ------------------------------------------------------------------
    // Access
    // ------------------------------------------------------------------

    async loadAccess() {
        this.isLoadingAccess = true;
        this.accessError = '';
        try {
            const info = await getAccessInfo();
            this.canCreate = !!(info && info.canCreate);
            this.missingPermissions = (info && info.missingPermissions) || [];
            this.usernameSuffix = info && info.usernameSuffix ? info.usernameSuffix : '';
            this.sendWelcomeEmail = !!(info && info.sendWelcomeEmail);
            this.sendPasswordResetEmail = info ? info.sendPasswordResetEmail !== false : true;
            this.sendVerificationEmail = info ? info.sendVerificationEmail !== false : true;
        } catch (error) {
            this.accessError = reduceErrors(error);
        } finally {
            this.isLoadingAccess = false;
        }
    }

    handleRetryAccess() {
        this.loadAccess();
    }

    // ------------------------------------------------------------------
    // Template state getters
    // ------------------------------------------------------------------

    get isNoAccess() {
        return !this.canCreate;
    }

    get isMissingPermissions() {
        return this.missingPermissions.length > 0;
    }

    get missingPermissionItems() {
        return this.missingPermissions.map((label) => ({ key: label, label }));
    }

    /** True when the clone user's licence type has none left, so a user like them can't be created. */
    get isOutOfLicences() {
        return !!this.cloneDetails && this.cloneDetails.licencesAvailable === 0;
    }

    get isStep1() {
        return this.step === 1;
    }

    get isStep2() {
        return this.step === 2;
    }

    get isStep3() {
        return this.step === 3;
    }

    get isStep4() {
        return this.step === 4;
    }

    get isLastStep() {
        return this.step === LAST_STEP;
    }

    get panelClass() {
        return this.direction === 'back' ? 'panel panel-back' : 'panel panel-forward';
    }

    // ------------------------------------------------------------------
    // Footer
    // ------------------------------------------------------------------

    get showBack() {
        return this.step > 1;
    }

    get nextLabel() {
        if (this.isLastStep) {
            return this.isCreating ? 'Creating…' : 'Create user';
        }
        return this.step === 3 ? 'Review' : 'Next';
    }

    get nextDisabled() {
        if (this.isCreating) {
            return true;
        }
        switch (this.step) {
            case 1:
                return !this.cloneSource || this.isLoadingClone || this.isOutOfLicences;
            case 3:
                return this.managerStatus === 'loading';
            default:
                return false;
        }
    }

    get primaryButtonClass() {
        let cls = 'btn btn-primary';
        if (this.isLastStep) {
            cls += ' btn-create';
        }
        if (this.isCreating) {
            cls += ' is-loading';
        }
        return cls;
    }

    get ariaBusyValue() {
        return this.isCreating ? 'true' : 'false';
    }

    get stepCounter() {
        return `Step ${this.step} of ${LAST_STEP}`;
    }

    // ------------------------------------------------------------------
    // Step 1: search
    // ------------------------------------------------------------------

    get hasSelectedUser() {
        return !!this.selectedUser;
    }

    get hasResults() {
        return this.searchResults.length > 0;
    }

    get searchBusyValue() {
        return this.isSearching ? 'true' : 'false';
    }

    get showNoResults() {
        return (
            this.searchTerm.trim().length >= MIN_SEARCH_LENGTH &&
            this.hasSearched &&
            !this.isSearching &&
            this.searchResults.length === 0
        );
    }

    get searchResultItems() {
        return this.searchResults.map((user, index) => ({
            ...user,
            animStyle: `animation-delay: ${Math.min(index, 10) * 35}ms`
        }));
    }


    handleSearchInput(event) {
        const value = event.detail.value || '';
        this.searchTerm = value;
        window.clearTimeout(this.searchTimer);
        // Any in-flight request is now stale.
        this.searchRequestId += 1;
        this.searchError = '';
        const term = value.trim();
        if (term.length < MIN_SEARCH_LENGTH) {
            this.searchResults = [];
            this.isSearching = false;
            this.hasSearched = false;
            return;
        }
        this.isSearching = true;
        // Debounce: search only once typing pauses, instead of calling Apex on every keystroke.
        this.searchTimer = window.setTimeout(() => this.runSearch(term), SEARCH_DEBOUNCE_MS);
    }

    async runSearch(term) {
        const requestId = this.searchRequestId;
        try {
            const users = await searchUsers({ searchTerm: term });
            if (requestId !== this.searchRequestId) {
                return;
            }
            this.searchResults = (users || []).map(toUserView);
            this.hasSearched = true;
            this.liveMessage =
                this.searchResults.length === 0
                    ? 'No users found.'
                    : `${pluralize(this.searchResults.length, 'user', 'users')} found.`;
        } catch (error) {
            if (requestId !== this.searchRequestId) {
                return;
            }
            this.searchResults = [];
            this.searchError = reduceErrors(error);
        } finally {
            if (requestId === this.searchRequestId) {
                this.isSearching = false;
            }
        }
    }

    handleRetrySearch() {
        const term = this.searchTerm.trim();
        if (term.length >= MIN_SEARCH_LENGTH) {
            this.searchError = '';
            this.isSearching = true;
            this.searchRequestId += 1;
            this.runSearch(term);
        }
    }

    // ------------------------------------------------------------------
    // Step 1: clone source
    // ------------------------------------------------------------------

    handleSelectUser(event) {
        const userId = event.currentTarget.dataset.id;
        const user = this.searchResults.find((item) => item.id === userId);
        if (!user) {
            return;
        }
        this.selectedUser = user;
        this.cloneUser = user;
        this.loadCloneSource(userId);
    }

    async loadCloneSource(userId) {
        this.isLoadingClone = true;
        this.cloneError = '';
        this.cloneSource = null;
        this.cloneDetails = null;
        this.selectedGroups = [];
        this.refreshGroupMatches();
        try {
            const source = await getCloneSource({ userId });
            if (!this.selectedUser || this.selectedUser.id !== userId) {
                return;
            }
            this.cloneSource = source;
            if (source && source.user) {
                this.cloneUser = toUserView(source.user);
            }
            this.cloneDetails = this.buildCloneDetails(source);
            this.selectedGroups = ((source && source.groups) || []).map((group) => ({ ...group }));
            this.groupFilter = '';
            this.refreshGroupMatches();
            this.liveMessage = `${this.cloneUser.name} selected. Details loaded.`;
        } catch (error) {
            if (this.selectedUser && this.selectedUser.id === userId) {
                this.cloneError = reduceErrors(error);
            }
        } finally {
            if (this.selectedUser && this.selectedUser.id === userId) {
                this.isLoadingClone = false;
            }
        }
    }

    buildCloneDetails(source) {
        const sets = toNamedItems(source.permissionSets);
        const setGroups = toNamedItems(source.permissionSetGroups);
        const licenses = toNamedItems(source.permissionSetLicenses);
        const groups = source.groups || [];
        const sections = [
            { key: 'ps', title: 'Permission sets', items: sets },
            { key: 'psg', title: 'Permission set groups', items: setGroups },
            { key: 'psl', title: 'Permission set licenses', items: licenses }
        ].filter((section) => section.items.length > 0);
        const licencesAvailable = typeof source.userLicensesAvailable === 'number' ? source.userLicensesAvailable : null;
        const exhausted = source.exhaustedPermissionSetLicenses || [];
        return {
            licencesAvailable,
            licenceName: source.userLicenseName || 'user',
            licencesLow: licencesAvailable !== null && licencesAvailable > 0 && licencesAvailable <= LOW_LICENCE_THRESHOLD,
            licencesLeftText:
                licencesAvailable === 1
                    ? `Only 1 ${source.userLicenseName} licence is left.`
                    : `Only ${licencesAvailable} ${source.userLicenseName} licences are left.`,
            exhaustedLicences: exhausted.join(', '),
            hasExhaustedLicences: exhausted.length > 0,
            profileName: this.cloneUser.profileName || 'Not available',
            roleName: this.cloneUser.roleName || 'No role',
            managerName: source.manager ? source.manager.name : 'No manager',
            stats: [
                { key: 'ps', label: 'Permission sets', value: sets.length },
                { key: 'psg', label: 'Permission set groups', value: setGroups.length },
                { key: 'psl', label: 'Licenses', value: licenses.length },
                { key: 'grp', label: 'Groups & queues', value: groups.length }
            ],
            sections,
            hasSections: sections.length > 0
        };
    }

    handleRetryClone() {
        if (this.selectedUser) {
            this.loadCloneSource(this.selectedUser.id);
        }
    }

    handleChangeUser() {
        this.selectedUser = null;
        this.cloneUser = null;
        this.cloneSource = null;
        this.cloneDetails = null;
        this.cloneError = '';
        this.isLoadingClone = false;
        this.selectedGroups = [];
        this.refreshGroupMatches();
        this.liveMessage = 'Clone user cleared. Search for another user.';
        this.focusPanelPending = true;
    }

    // ------------------------------------------------------------------
    // Step 2: new user
    // ------------------------------------------------------------------

    get normalizedEmail() {
        return (this.email || '').trim().toLowerCase();
    }

    /** Mirrors the Apex rule: email.trim().toLowerCase() + suffix.trim() */
    get usernameSuffixValue() {
        return this.usernameSuffix ? this.usernameSuffix.trim() : '';
    }

    get previewLocal() {
        return this.normalizedEmail || 'email@company.com';
    }

    get previewLocalClass() {
        return this.normalizedEmail ? 'preview-local' : 'preview-local is-placeholder';
    }

    get hasUsernameSuffix() {
        return this.usernameSuffixValue.length > 0;
    }

    get fullName() {
        return [this.firstName.trim(), this.lastName.trim()].filter(Boolean).join(' ');
    }

    get newUserInitials() {
        return getInitials(this.fullName);
    }

    handleFieldChange(event) {
        const name = event.target.name;
        if (EDITABLE_FIELDS.includes(name)) {
            this[name] = event.detail.value || '';
            event.target.setCustomValidity('');
        }
    }

    // ------------------------------------------------------------------
    // Step 3: manager
    // ------------------------------------------------------------------

    get isManagerLoading() {
        return this.managerStatus === 'loading';
    }

    get isManagerFound() {
        return this.managerStatus === 'found' && !!this.manager;
    }

    get isManagerNotFound() {
        return this.managerStatus === 'notfound';
    }

    get isManagerError() {
        return this.managerStatus === 'error';
    }

    get cloneManagerName() {
        return this.cloneSource && this.cloneSource.manager ? this.cloneSource.manager.name : '';
    }

    get managerHint() {
        if (this.managerEmail.trim()) {
            return 'We will look this person up when you leave the field.';
        }
        return this.cloneManagerName
            ? `Leave blank to use the clone user's manager: ${this.cloneManagerName}.`
            : 'Leave blank for no manager. The clone user does not have one.';
    }

    get managerView() {
        return this.manager ? toUserView(this.manager) : null;
    }

    handleManagerChange(event) {
        this.managerEmail = event.detail.value || '';
        event.target.setCustomValidity('');
        this.managerStatus = '';
        this.manager = null;
        this.managerLookupKey = '';
    }

    handleManagerBlur() {
        this.resolveManager();
    }

    /** Resolves the manager email. Returns true when the email is blank or a user was found. */
    async resolveManager() {
        const email = this.managerEmail.trim();
        if (!email) {
            this.managerStatus = '';
            this.manager = null;
            this.managerLookupKey = '';
            return true;
        }
        const input = this.template.querySelector('lightning-input[name="managerEmail"]');
        if (input && !input.checkValidity()) {
            return false;
        }
        const key = email.toLowerCase();
        if (this.managerLookupKey === key && this.managerStatus !== 'loading' && this.managerStatus !== 'error') {
            return this.managerStatus === 'found';
        }
        this.managerLookupKey = key;
        this.managerStatus = 'loading';
        this.manager = null;
        try {
            const found = await findUserByEmail({ email });
            if (this.managerLookupKey !== key) {
                return false;
            }
            if (found) {
                this.manager = found;
                this.managerStatus = 'found';
                this.liveMessage = `Manager found: ${found.name}.`;
                return true;
            }
            this.managerStatus = 'notfound';
            this.liveMessage = 'No active user found with that manager email.';
            return false;
        } catch (error) {
            if (this.managerLookupKey === key) {
                this.managerStatus = 'error';
                this.managerError = reduceErrors(error);
            }
            return false;
        }
    }

    // ------------------------------------------------------------------
    // Step 3: groups and queues
    // ------------------------------------------------------------------

    decorateGroup(group) {
        const isQueue = group.type === 'Queue';
        return {
            id: group.id,
            label: group.label || group.developerName,
            developerName: group.developerName,
            typeLabel: isQueue ? 'Queue' : 'Group',
            iconName: isQueue ? 'standard:queue' : 'standard:groups',
            badgeClass: isQueue ? 'badge badge-queue' : 'badge badge-group',
            addLabel: `Add ${isQueue ? 'queue' : 'group'} ${group.label || group.developerName}`
        };
    }

    get selectedGroupItems() {
        return this.selectedGroups.map((group) => this.decorateGroup(group));
    }

    get hasSelectedGroups() {
        return this.selectedGroups.length > 0;
    }

    get selectedGroupCount() {
        return this.selectedGroups.length;
    }

    get groupsPrefilled() {
        return !!this.cloneUser && this.hasSelectedGroups;
    }

    get hasAvailableGroups() {
        return this.availableGroupItems.length > 0;
    }

    get groupMatchSummary() {
        if (this.groupMatchTotal > MAX_GROUP_MATCHES) {
            return `Showing ${MAX_GROUP_MATCHES} of ${this.groupMatchTotal} matches. Type to narrow the list.`;
        }
        return `${pluralize(this.groupMatchTotal, 'match', 'matches')}.`;
    }

    get showGroupEmpty() {
        return this.groupsLoaded && !this.isLoadingGroups && !this.groupsError && !this.hasAvailableGroups;
    }

    get groupEmptyMessage() {
        return this.groupFilter.trim()
            ? 'No groups or queues match your filter.'
            : 'Every available group and queue is already selected.';
    }

    async loadGroups() {
        if (this.groupsLoaded || this.isLoadingGroups) {
            return;
        }
        this.isLoadingGroups = true;
        this.groupsError = '';
        try {
            const groups = await getGroupsAndQueues();
            this.allGroups = groups || [];
            this.groupsLoaded = true;
            this.refreshGroupMatches();
        } catch (error) {
            this.groupsError = reduceErrors(error);
        } finally {
            this.isLoadingGroups = false;
        }
    }

    handleRetryGroups() {
        this.loadGroups();
    }

    refreshGroupMatches() {
        const selectedIds = new Set(this.selectedGroups.map((group) => group.id));
        const term = this.groupFilter.trim().toLowerCase();
        const matches = this.allGroups.filter((group) => {
            if (selectedIds.has(group.id)) {
                return false;
            }
            if (!term) {
                return true;
            }
            return (
                (group.label || '').toLowerCase().includes(term) ||
                (group.developerName || '').toLowerCase().includes(term)
            );
        });
        this.groupMatchTotal = matches.length;
        this.availableGroupItems = matches.slice(0, MAX_GROUP_MATCHES).map((group) => this.decorateGroup(group));
    }

    handleGroupFilter(event) {
        this.groupFilter = event.detail.value || '';
        this.refreshGroupMatches();
    }

    handleAddGroup(event) {
        const groupId = event.currentTarget.dataset.id;
        const group = this.allGroups.find((item) => item.id === groupId);
        if (!group || this.selectedGroups.some((item) => item.id === groupId)) {
            return;
        }
        this.selectedGroups = [...this.selectedGroups, { ...group }];
        this.refreshGroupMatches();
        this.liveMessage = `${group.label || group.developerName} added.`;
    }

    handleRemoveGroup(event) {
        const groupId = event.target.name || (event.detail && event.detail.name);
        const group = this.selectedGroups.find((item) => item.id === groupId);
        this.selectedGroups = this.selectedGroups.filter((item) => item.id !== groupId);
        this.refreshGroupMatches();
        if (group) {
            this.liveMessage = `${group.label || group.developerName} removed.`;
        }
    }

    // ------------------------------------------------------------------
    // Step 4: review
    // ------------------------------------------------------------------

    get reviewManagerName() {
        if (this.managerEmail.trim() && this.manager) {
            return this.manager.name;
        }
        return this.cloneManagerName || 'No manager';
    }

    get reviewManagerNote() {
        if (this.managerEmail.trim() && this.manager) {
            return this.manager.email;
        }
        return this.cloneManagerName ? 'Same as the clone user' : '';
    }

    get welcomeEmailNote() {
        const emails = [];
        if (this.sendPasswordResetEmail) {
            emails.push('a password reset email to set their password');
        } else if (this.sendWelcomeEmail) {
            emails.push('the standard welcome email');
        }
        if (this.sendVerificationEmail) {
            emails.push('an email address verification link');
        }
        return emails.length
            ? `The new user will receive ${emails.join(' and ')}.`
            : 'No emails will be sent. Share sign-in details with the user yourself.';
    }

    // ------------------------------------------------------------------
    // Navigation
    // ------------------------------------------------------------------

    goTo(target) {
        if (target === this.step) {
            return;
        }
        this.direction = target > this.step ? 'forward' : 'back';
        this.step = target;
        this.focusPanelPending = true;
        this.liveMessage = `${this.stepCounter}: ${STEP_TITLES[target]}.`;
        if (target === 3) {
            this.loadGroups();
        }
    }

    handleBack() {
        if (this.step > 1 && !this.isCreating) {
            this.goTo(this.step - 1);
        }
    }

    async handleNext() {
        if (this.nextDisabled) {
            return;
        }
        if (this.isLastStep) {
            await this.submit();
            return;
        }
        const valid = await this.validateCurrentStep();
        if (valid) {
            this.goTo(this.step + 1);
        }
    }

    handleStepSelect(event) {
        const target = event.detail;
        if (!this.isCreating && target < this.step) {
            this.goTo(target);
        }
    }

    handleEditStep(event) {
        const target = Number(event.currentTarget.dataset.step);
        if (!this.isCreating && target >= 1 && target < this.step) {
            this.goTo(target);
        }
    }

    async validateCurrentStep() {
        if (this.step === 1) {
            return !!this.cloneSource && !this.isOutOfLicences;
        }
        if (this.step === 2) {
            return this.validateInputs('lightning-input[data-validate]');
        }
        if (this.step === 3) {
            return this.validateManager();
        }
        return true;
    }

    validateInputs(selector) {
        let valid = true;
        this.template.querySelectorAll(selector).forEach((input) => {
            if (input.required && !String(input.value || '').trim()) {
                input.setCustomValidity('Complete this field.');
            } else {
                input.setCustomValidity('');
            }
            if (!input.reportValidity()) {
                valid = false;
            }
        });
        return valid;
    }

    async validateManager() {
        const ok = await this.resolveManager();
        if (ok) {
            return true;
        }
        const input = this.template.querySelector('lightning-input[name="managerEmail"]');
        if (input) {
            if (this.managerStatus === 'notfound') {
                input.setCustomValidity('No active user found with this email.');
            }
            input.reportValidity();
        }
        return false;
    }

    // ------------------------------------------------------------------
    // Create
    // ------------------------------------------------------------------

    async submit() {
        if (!this.canCreate || this.isCreating) {
            return;
        }
        this.isCreating = true;
        this.createError = '';
        this.liveMessage = 'Creating the new user.';
        try {
            const request = {
                cloneUserId: this.selectedUser.id,
                firstName: this.firstName.trim(),
                lastName: this.lastName.trim(),
                email: this.email.trim(),
                managerEmail: this.managerEmail.trim() || null,
                groupIds: this.selectedGroups.map((group) => group.id)
            };
            const outcome = await createUser({ request });
            this.result = outcome;
            this.isSuccess = true;
            this.focusPanelPending = true;
            this.liveMessage = `${outcome.name} was created.`;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'User created',
                    message: `${outcome.name} (${outcome.username}) is ready.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.createError = reduceErrors(error);
            this.liveMessage = 'Creating the user failed.';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not create user',
                    message: this.createError,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this.isCreating = false;
        }
    }

    // ------------------------------------------------------------------
    // Success state
    // ------------------------------------------------------------------

    get successTitle() {
        return this.firstName.trim() ? `Welcome aboard, ${this.firstName.trim()}!` : 'User created!';
    }

    get resultStats() {
        const outcome = this.result || {};
        return [
            { key: 'ps', label: 'Permission sets', value: outcome.permissionSetsAssigned || 0 },
            { key: 'psg', label: 'Permission set groups', value: outcome.permissionSetGroupsAssigned || 0 },
            { key: 'psl', label: 'Licenses', value: outcome.licensesAssigned || 0 },
            { key: 'grp', label: 'Groups & queues', value: outcome.groupsAssigned || 0 }
        ];
    }

    get warningItems() {
        const warnings = (this.result && this.result.warnings) || [];
        return warnings.map((text, index) => ({ key: `warning-${index}`, text }));
    }

    get hasWarnings() {
        return this.warningItems.length > 0;
    }

    get warningTitle() {
        return `${pluralize(this.warningItems.length, 'item needs', 'items need')} your attention`;
    }

    get successEmailNote() {
        const outcome = this.result || {};
        const emails = [];
        if (outcome.passwordResetEmailSent) {
            emails.push('a password reset email');
        } else if (this.sendWelcomeEmail && !this.sendPasswordResetEmail) {
            emails.push('a welcome email');
        }
        if (outcome.verificationEmailSent) {
            emails.push('an email verification link');
        }
        return emails.length
            ? `Sent ${emails.join(' and ')} to the new user.`
            : 'No onboarding emails were sent. Share sign-in details with the user yourself.';
    }

    get resultManagerLine() {
        return this.result && this.result.managerName ? `Manager: ${this.result.managerName}` : 'No manager assigned';
    }

    handleOpenRecord() {
        if (!this.result || !this.result.userId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.result.userId,
                objectApiName: 'User',
                actionName: 'view'
            }
        });
    }

    handleReset() {
        window.clearTimeout(this.searchTimer);
        this.searchRequestId += 1;
        this.step = 1;
        this.direction = 'forward';
        this.searchTerm = '';
        this.isSearching = false;
        this.hasSearched = false;
        this.searchError = '';
        this.searchResults = [];
        this.selectedUser = null;
        this.cloneUser = null;
        this.cloneSource = null;
        this.cloneDetails = null;
        this.isLoadingClone = false;
        this.cloneError = '';
        this.firstName = '';
        this.lastName = '';
        this.email = '';
        this.managerEmail = '';
        this.managerStatus = '';
        this.managerError = '';
        this.manager = null;
        this.managerLookupKey = '';
        this.selectedGroups = [];
        this.groupFilter = '';
        this.refreshGroupMatches();
        this.createError = '';
        this.result = null;
        this.isSuccess = false;
        this.focusPanelPending = true;
        this.liveMessage = 'Ready to onboard another user. Step 1 of 4.';
    }
}
