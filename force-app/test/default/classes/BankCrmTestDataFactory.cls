/**
 * Shared test data helpers for Bank CRM Apex suites.
 */
@IsTest
public class BankCrmTestDataFactory {
    private static Integer customerSequence = 0;
    private static Integer externalIdSequence = 0;

    public static void bypassTriggerForServiceTests() {
        LoanRequestTriggerHandler.bypassTrigger = true;
    }

    public static void enableTrigger() {
        LoanRequestTriggerHandler.bypassTrigger = false;
    }

    public static Customer__c createCustomer(Boolean doInsert) {
        return createCustomer(null, doInsert);
    }

    public static Customer__c createCustomer(Id relationshipManagerId, Boolean doInsert) {
        customerSequence++;
        Customer__c customer = new Customer__c(
            Name = 'Test Customer ' + customerSequence,
            CustomerNumber__c = 'CUST-' + String.valueOf(customerSequence).leftPad(4, '0'),
            Email__c = 'customer' + customerSequence + '@example.com',
            Status__c = 'Prospect',
            IsActive__c = true,
            RelationshipManager__c = relationshipManagerId
        );
        if (doInsert) {
            insert customer;
        }
        return customer;
    }

    public static Customer__c createInactiveCustomer(Boolean doInsert) {
        Customer__c customer = createCustomer(UserInfo.getUserId(), false);
        customer.IsActive__c = false;
        customer.Status__c = 'Inactive';
        if (doInsert) {
            insert customer;
        }
        return customer;
    }

    public static LoanRequest__c buildLoanRequest(
        Id customerId,
        Decimal amount,
        String status
    ) {
        LoanRequest__c loan = new LoanRequest__c(
            Customer__c = customerId,
            LoanAmount__c = amount,
            LoanStatus__c = status,
            IntegrationStatus__c = 'Not Sent',
            HighValueTaskCreated__c = false
        );
        if (status != null && status != 'Draft') {
            loan.SubmissionDate__c = System.now();
        }
        return loan;
    }

    public static LoanRequest__c createLoanRequest(
        Id customerId,
        Decimal amount,
        String status,
        Boolean doInsert
    ) {
        LoanRequest__c loan = buildLoanRequest(customerId, amount, status);
        if (doInsert) {
            insert loan;
        }
        return loan;
    }

    public static LoanRequest__c createHighValueLoan(
        Id customerId,
        Decimal threshold,
        Boolean doInsert
    ) {
        return createLoanRequest(customerId, threshold + 1, 'Draft', doInsert);
    }

    public static LoanRequest__c createBelowThresholdLoan(
        Id customerId,
        Decimal threshold,
        Boolean doInsert
    ) {
        return createLoanRequest(customerId, threshold, 'Draft', doInsert);
    }

    public static LoanRequest__c buildIntegrationLoan(
        Id customerId,
        String integrationStatus,
        Datetime lastAttempt,
        String externalRequestId
    ) {
        LoanRequest__c loan = buildLoanRequest(customerId, 1000, 'Submitted');
        loan.SubmissionDate__c = System.now();
        loan.IntegrationStatus__c = integrationStatus;
        loan.IntegrationLastAttempt__c = lastAttempt;
        loan.ExternalRequestId__c = externalRequestId;
        return loan;
    }

    public static Audit__c buildStatusChangedAudit(Id loanId, Id customerId, String customerName) {
        return new Audit__c(
            LoanRequest__c = loanId,
            Customer__c = customerId,
            EventType__c = 'STATUS_CHANGED',
            OldValue__c = 'Draft',
            NewValue__c = 'Submitted',
            CustomerNameSnapshot__c = customerName,
            LoanAmountSnapshot__c = 1000,
            OccurredAt__c = System.now(),
            ActorUser__c = UserInfo.getUserId(),
            CorrelationId__c = CorrelationIdUtil.newId(),
            Source__c = 'Apex',
            Details__c = 'Test status change'
        );
    }

    public static Application_Error__c buildApplicationError(
        String category,
        Boolean retryable,
        String resolutionStatus,
        Datetime nextRetryAt
    ) {
        return new Application_Error__c(
            SourceComponent__c = 'BankCrmTestDataFactory',
            Operation__c = 'unit-test',
            CorrelationId__c = CorrelationIdUtil.newId(),
            OccurredAt__c = System.now(),
            Category__c = category,
            IsRetryable__c = retryable,
            AttemptCount__c = retryable ? 1 : 0,
            NextRetryAt__c = nextRetryAt,
            SanitizedMessage__c = 'Sanitized test error message',
            ResolutionStatus__c = resolutionStatus
        );
    }

    public static String nextExternalRequestId() {
        externalIdSequence++;
        return 'EXT-' + String.valueOf(externalIdSequence).leftPad(6, '0');
    }

    public static BankCrmSettings buildSettings(Decimal threshold) {
        return new BankCrmSettings(
            threshold,
            null,
            'Bank_CRM_Default_Manager',
            'High_Value_Loan_Review',
            3,
            false,
            15,
            'Default'
        );
    }

    public static BankCrmSettings buildIntegrationEnabledSettings(Decimal threshold) {
        return new BankCrmSettings(
            threshold,
            null,
            'Bank_CRM_Default_Manager',
            'High_Value_Loan_Review',
            3,
            true,
            15,
            'Default'
        );
    }

    public static BankCrmSettings buildIntegrationEnabledSettings(
        Decimal threshold,
        Integer retryLimit,
        Integer retryBaseDelayMinutes
    ) {
        return new BankCrmSettings(
            threshold,
            null,
            'Bank_CRM_Default_Manager',
            'High_Value_Loan_Review',
            retryLimit,
            true,
            retryBaseDelayMinutes,
            'Default'
        );
    }

    public static BankCrmSettings buildSettings(
        Decimal threshold,
        String defaultManagerUsername,
        String defaultQueueDeveloperName
    ) {
        return new BankCrmSettings(
            threshold,
            defaultManagerUsername,
            defaultQueueDeveloperName,
            'High_Value_Loan_Review',
            3,
            false,
            15,
            'Default'
        );
    }

    public static DomainExecutionContext buildContext(BankCrmSettings settings) {
        return DomainExecutionContext.forCurrentUser(settings);
    }

    public static User createStandardUser(String key) {
        Profile profile = resolveRestrictedProfile();
        String unique = key + String.valueOf(Crypto.getRandomInteger());
        User user = new User(
            Alias = unique.left(8),
            Email = unique + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'BankCrmTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = unique + '@bankcrm.test'
        );
        insert user;
        return user;
    }

    public static void assignPermissionSet(User user, String permissionSetApiName) {
        if (user == null || String.isBlank(permissionSetApiName)) {
            return;
        }
        List<PermissionSet> sets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :permissionSetApiName
            LIMIT 1
        ];
        System.assert(
            !sets.isEmpty(),
            'Permission set not found: ' + permissionSetApiName
        );
        insert new PermissionSetAssignment(
            AssigneeId = user.Id,
            PermissionSetId = sets[0].Id
        );
    }

    private static Profile resolveRestrictedProfile() {
        List<Profile> profiles = [
            SELECT Id, Name
            FROM Profile
            WHERE Name IN ('Standard User', 'Salesforce Platform', 'Minimum Access - Salesforce')
            ORDER BY Name
            LIMIT 1
        ];
        System.assert(
            !profiles.isEmpty(),
            'Expected a standard profile for persona tests.'
        );
        return profiles[0];
    }
}
