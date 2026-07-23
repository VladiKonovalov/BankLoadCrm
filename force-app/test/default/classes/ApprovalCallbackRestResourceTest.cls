@IsTest
private class ApprovalCallbackRestResourceTest {
    private static LoanRequest__c seedPendingLoan() {
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildIntegrationEnabledSettings(250000)
        );
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.buildIntegrationLoan(
            customer.Id,
            'Pending',
            System.now(),
            BankCrmTestDataFactory.nextExternalRequestId()
        );
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        insert loan;
        BankCrmTestDataFactory.enableTrigger();
        return loan;
    }

    private static void setupRest(String body, String token) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/bankcrm/v1/approval-callback';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        if (String.isNotBlank(token)) {
            req.addHeader('X-Bank-CRM-Callback-Token', token);
        }
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        ApprovalCallbackRestResource.testAuthToken = 'test-callback-token';
    }

    @IsTest
    static void doPost_unauthorized_returns401() {
        setupRest('{}', 'wrong-token');
        Test.startTest();
        ApprovalCallbackRestResource.doPost();
        Test.stopTest();
        System.assertEquals(401, RestContext.response.statusCode);
    }

    @IsTest
    static void doPost_validCallback_returns200() {
        LoanRequest__c loan = seedPendingLoan();
        String body = JSON.serialize(
            new Map<String, Object>{
                'externalRequestId' => loan.ExternalRequestId__c,
                'externalDecisionReference' => 'DEC-REST-1',
                'decision' => 'Rejected',
                'decisionReason' => 'Insufficient documentation',
                'correlationId' => CorrelationIdUtil.newId()
            }
        );
        setupRest(body, 'test-callback-token');

        Test.startTest();
        ApprovalCallbackRestResource.doPost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        LoanRequest__c refreshed = [
            SELECT LoanStatus__c, IntegrationStatus__c, DecisionReason__c
            FROM LoanRequest__c
            WHERE Id = :loan.Id
        ];
        System.assertEquals('Rejected', refreshed.LoanStatus__c);
        System.assertEquals('Succeeded', refreshed.IntegrationStatus__c);
        System.assertEquals('Insufficient documentation', refreshed.DecisionReason__c);
    }

    @IsTest
    static void doPost_blankBody_returns400() {
        setupRest(' ', 'test-callback-token');
        Test.startTest();
        ApprovalCallbackRestResource.doPost();
        Test.stopTest();
        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest
    static void doPost_unknownExternalId_returns400() {
        setupRest(
            '{"externalRequestId":"MISSING-EXT","decision":"Approved","correlationId":"c-1"}',
            'test-callback-token'
        );
        Test.startTest();
        ApprovalCallbackRestResource.doPost();
        Test.stopTest();
        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest
    static void doPost_missingTokenHeader_returns401() {
        setupRest('{}', null);
        Test.startTest();
        ApprovalCallbackRestResource.doPost();
        Test.stopTest();
        System.assertEquals(401, RestContext.response.statusCode);
    }
}