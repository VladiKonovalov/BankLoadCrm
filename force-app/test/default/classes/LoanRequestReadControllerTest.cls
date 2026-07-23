@IsTest
private class LoanRequestReadControllerTest {
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
    static void getLoanRequest_returnsDisplayFieldsOnly() {
        setup();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            4200,
            'Draft',
            true
        );

        Test.startTest();
        LoanRequestDto dto = LoanRequestReadController.getLoanRequest(loan.Id);
        Test.stopTest();

        System.assertEquals(loan.Id, dto.id);
        System.assertEquals(customer.Name, dto.customerName);
        System.assertEquals(4200, dto.loanAmount);
        System.assertEquals('Draft', dto.loanStatus);
        System.assertEquals(null, dto.customerId);

        String serialized = JSON.serialize(dto);
        System.assert(!serialized.contains('ExternalRequestId'));
        System.assert(!serialized.contains('NationalIdentifier'));
        System.assert(!serialized.contains('DecisionReason'));
        System.assert(!serialized.contains('IntegrationStatus'));
    }

    @IsTest
    static void getLoanRequest_nullId_throwsAura() {
        setup();
        Boolean thrown = false;
        try {
            LoanRequestReadController.getLoanRequest(null);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void getLoanRequest_unknownId_throwsAura() {
        setup();
        // Synthesize a loan Id that will not match any row.
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c temp = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            100,
            'Draft',
            true
        );
        Id missingId = temp.Id;
        delete temp;

        Boolean thrown = false;
        try {
            LoanRequestReadController.getLoanRequest(missingId);
        } catch (AuraHandledException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void getLoanRequest_userWithoutReadAccess_throws() {
        setup();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Draft',
            true
        );
        User restricted = createStandardUser('noread');

        Boolean thrown = false;
        System.runAs(restricted) {
            try {
                LoanRequestReadController.getLoanRequest(loan.Id);
            } catch (AuraHandledException ex) {
                thrown = true;
            } catch (Exception ex) {
                thrown = ex instanceof BankCrmException.AuthorizationException
                    || ex instanceof AuraHandledException
                    || ex instanceof System.QueryException;
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
