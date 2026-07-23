@IsTest
private class LoanRequestControllerTest {
    private static void setup() {
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(
                250000,
                null,
                'Bank_CRM_Default_Manager'
            )
        );
        BankCrmTestDataFactory.enableTrigger();
    }

    @IsTest
    static void saveLoanRequest_happyPath_returnsIdAndCorrelation() {
        setup();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequestDto dto = new LoanRequestDto();
        dto.customerId = customer.Id;
        dto.loanAmount = 1500;
        dto.loanStatus = 'Draft';

        Test.startTest();
        SaveResultDto result = LoanRequestController.saveLoanRequest(dto);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertNotEquals(null, result.loanRequestId);
        System.assertNotEquals(null, result.correlationId);
        System.assertEquals(0, result.errors.size());

        LoanRequest__c loaded = [
            SELECT Customer__c, LoanAmount__c, LoanStatus__c, IntegrationStatus__c
            FROM LoanRequest__c
            WHERE Id = :result.loanRequestId
        ];
        System.assertEquals(customer.Id, loaded.Customer__c);
        System.assertEquals(1500, loaded.LoanAmount__c);
        System.assertEquals('Draft', loaded.LoanStatus__c);
        System.assertEquals('Not Sent', loaded.IntegrationStatus__c);
    }

    @IsTest
    static void saveLoanRequest_invalidInput_returnsFailures_noInsert() {
        setup();
        Integer beforeCount = [SELECT COUNT() FROM LoanRequest__c];
        LoanRequestDto dto = new LoanRequestDto();
        dto.loanAmount = 0;
        dto.loanStatus = 'Approved';

        SaveResultDto result = LoanRequestController.saveLoanRequest(dto);

        System.assertEquals(false, result.success);
        System.assertEquals(null, result.loanRequestId);
        System.assertNotEquals(null, result.correlationId);
        System.assert(result.errors.size() >= 2);
        System.assertEquals(beforeCount, [SELECT COUNT() FROM LoanRequest__c]);
    }

    @IsTest
    static void saveLoanRequest_submittedIncompleteCustomer_returnsFailures() {
        setup();
        Customer__c customer = BankCrmTestDataFactory.createInactiveCustomer(true);
        LoanRequestDto dto = new LoanRequestDto();
        dto.customerId = customer.Id;
        dto.loanAmount = 2000;
        dto.loanStatus = 'Submitted';

        SaveResultDto result = LoanRequestController.saveLoanRequest(dto);

        System.assertEquals(false, result.success);
        System.assertEquals(null, result.loanRequestId);
        Boolean hasCustomerFailure = false;
        for (ValidationFailure failure : result.errors) {
            if (failure.fieldApiName == 'customerId') {
                hasCustomerFailure = true;
            }
        }
        System.assertEquals(true, hasCustomerFailure);
    }

    @IsTest
    static void saveLoanRequest_submitted_stampsSubmissionDate() {
        setup();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequestDto dto = new LoanRequestDto();
        dto.customerId = customer.Id;
        dto.loanAmount = 3000;
        dto.loanStatus = 'Submitted';

        Test.startTest();
        SaveResultDto result = LoanRequestController.saveLoanRequest(dto);
        Test.stopTest();

        System.assertEquals(true, result.success);
        LoanRequest__c loaded = [
            SELECT SubmissionDate__c, LoanStatus__c
            FROM LoanRequest__c
            WHERE Id = :result.loanRequestId
        ];
        System.assertEquals('Submitted', loaded.LoanStatus__c);
        System.assertNotEquals(null, loaded.SubmissionDate__c);
    }

    @IsTest
    static void saveLoanRequest_nullDto_returnsFailure() {
        setup();
        SaveResultDto result = LoanRequestController.saveLoanRequest(null);
        System.assertEquals(false, result.success);
        System.assert(!result.errors.isEmpty());
    }

    @IsTest
    static void saveLoanRequest_dtoOmitsSensitiveFields() {
        LoanRequestDto dto = new LoanRequestDto();
        dto.customerId = UserInfo.getUserId();
        dto.loanAmount = 100;
        dto.loanStatus = 'Draft';
        LoanRequest__c record = dto.toSObject();
        Map<String, Object> fields = record.getPopulatedFieldsAsMap();
        System.assert(!fields.containsKey('ExternalRequestId__c'));
        System.assert(!fields.containsKey('NationalIdentifier__c'));
        System.assert(!fields.containsKey('DecisionReason__c'));
        System.assert(!fields.containsKey('IntegrationStatus__c'));
    }

    @IsTest
    static void saveLoanRequest_userWithoutCreateAccess_throwsAura() {
        setup();
        User restricted = createStandardUser('nocreate');
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequestDto dto = new LoanRequestDto();
        dto.customerId = customer.Id;
        dto.loanAmount = 1000;
        dto.loanStatus = 'Draft';

        Boolean thrown = false;
        System.runAs(restricted) {
            try {
                LoanRequestController.saveLoanRequest(dto);
            } catch (AuraHandledException ex) {
                thrown = true;
            } catch (Exception ex) {
                // Some orgs surface AuthorizationException before Aura wrap in tests.
                thrown = ex instanceof BankCrmException.AuthorizationException
                    || ex instanceof AuraHandledException;
            }
        }
        System.assertEquals(true, thrown);
    }

    private static User createStandardUser(String key) {
        Profile profile = resolveRestrictedProfile();
        String unique = key + String.valueOf(Crypto.getRandomInteger());
        User user = new User(
            Alias = unique.left(8),
            Email = unique + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Restricted',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = unique + '@bankcrm.test'
        );
        insert user;
        return user;
    }

    private static Profile resolveRestrictedProfile() {
        List<Profile> profiles = [
            SELECT Id, Name
            FROM Profile
            WHERE Name IN ('Standard User', 'Salesforce Platform', 'Minimum Access - Salesforce')
            ORDER BY Name
            LIMIT 1
        ];
        System.assert(!profiles.isEmpty(), 'Expected a standard profile for restricted-user tests.');
        return profiles[0];
    }
}
