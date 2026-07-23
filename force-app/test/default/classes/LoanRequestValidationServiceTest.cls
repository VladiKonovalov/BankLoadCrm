@IsTest
private class LoanRequestValidationServiceTest {
    private static void isolateFromTrigger() {
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(250000)
        );
    }

    @IsTest
    static void validateForLwcCreate_happyPath_returnsNoFailures() {
        isolateFromTrigger();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequestDto dto = new LoanRequestDto();
        dto.customerId = customer.Id;
        dto.loanAmount = 1000;
        dto.loanStatus = 'Draft';

        List<ValidationFailure> failures = LoanRequestValidationService.validateForLwcCreate(dto);
        System.assertEquals(0, failures.size());
    }

    @IsTest
    static void validateForLwcCreate_incompleteDto_returnsFieldFailures() {
        isolateFromTrigger();
        LoanRequestDto dto = new LoanRequestDto();
        dto.loanAmount = 0;
        dto.loanStatus = 'Approved';

        List<ValidationFailure> failures = LoanRequestValidationService.validateForLwcCreate(dto);
        Set<String> fields = new Set<String>();
        for (ValidationFailure failure : failures) {
            fields.add(failure.fieldApiName);
        }
        System.assert(fields.contains('customerId'));
        System.assert(fields.contains('loanAmount'));
        System.assert(fields.contains('loanStatus'));
    }

    @IsTest
    static void validateBeforeInsert_negativeAmount_capturesError() {
        isolateFromTrigger();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.buildLoanRequest(
            customer.Id,
            -10,
            'Draft'
        );
        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(250000);
        LoanRequestValidationService.capturedTriggerErrors = new List<String>();

        Test.startTest();
        LoanRequestValidationService.validateBeforeInsert(
            new List<LoanRequest__c>{ loan },
            BankCrmTestDataFactory.buildContext(settings)
        );
        Test.stopTest();

        System.assert(
            String.join(LoanRequestValidationService.capturedTriggerErrors, '|')
                .contains('LoanAmount__c')
        );
    }

    @IsTest
    static void validateBeforeUpdate_illegalTransition_capturesError() {
        isolateFromTrigger();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c oldLoan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Draft',
            true
        );
        LoanRequest__c newLoan = oldLoan.clone(true, true, true, true);
        newLoan.LoanStatus__c = 'Approved';
        newLoan.SubmissionDate__c = System.now();

        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(250000);
        LoanRequestValidationService.capturedTriggerErrors = new List<String>();

        Test.startTest();
        LoanRequestValidationService.validateBeforeUpdate(
            new List<LoanRequest__c>{ newLoan },
            new Map<Id, LoanRequest__c>{ oldLoan.Id => oldLoan },
            BankCrmTestDataFactory.buildContext(settings)
        );
        Test.stopTest();

        System.assert(
            String.join(LoanRequestValidationService.capturedTriggerErrors, '|')
                .contains('not allowed')
        );
    }

    @IsTest
    static void validateBeforeUpdate_terminalStatus_protectedForOrdinaryUser() {
        isolateFromTrigger();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c oldLoan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Draft',
            true
        );
        oldLoan.LoanStatus__c = 'Approved';
        oldLoan.SubmissionDate__c = System.now();
        update oldLoan;

        LoanRequest__c newLoan = oldLoan.clone(true, true, true, true);
        newLoan.LoanStatus__c = 'Submitted';

        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(250000);
        LoanRequestValidationService.capturedTriggerErrors = new List<String>();

        // Assumes running user lacks Reopen_Final_Loan_Decision (do not assign
        // Bank_CRM_Approver to the Apex test runner).
        System.assertEquals(
            false,
            ApexSecurityHelper.canReopenFinalLoanDecision(),
            'Test runner must not have Reopen_Final_Loan_Decision'
        );

        Test.startTest();
        LoanRequestValidationService.validateBeforeUpdate(
            new List<LoanRequest__c>{ newLoan },
            new Map<Id, LoanRequest__c>{ oldLoan.Id => oldLoan },
            BankCrmTestDataFactory.buildContext(settings)
        );
        Test.stopTest();

        System.assert(
            String.join(LoanRequestValidationService.capturedTriggerErrors, '|')
                .contains('final')
        );
    }

    @IsTest
    static void validateBeforeUpdate_protectedIntegrationField_denied() {
        isolateFromTrigger();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c oldLoan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Submitted',
            true
        );
        LoanRequest__c newLoan = oldLoan.clone(true, true, true, true);
        newLoan.ExternalRequestId__c = 'HACK-1';
        newLoan.IntegrationStatus__c = 'Pending';

        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(250000);
        LoanRequestValidationService.capturedTriggerErrors = new List<String>();

        Test.startTest();
        LoanRequestValidationService.validateBeforeUpdate(
            new List<LoanRequest__c>{ newLoan },
            new Map<Id, LoanRequest__c>{ oldLoan.Id => oldLoan },
            BankCrmTestDataFactory.buildContext(settings)
        );
        Test.stopTest();

        String joined = String.join(LoanRequestValidationService.capturedTriggerErrors, '|');
        System.assert(joined.contains('ExternalRequestId__c'));
        System.assert(joined.contains('IntegrationStatus__c'));
    }

    @IsTest
    static void validateBeforeUpdate_rejectionRequiresReason() {
        isolateFromTrigger();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c oldLoan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Submitted',
            true
        );
        LoanRequest__c newLoan = oldLoan.clone(true, true, true, true);
        newLoan.LoanStatus__c = 'Rejected';

        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(250000);
        LoanRequestValidationService.capturedTriggerErrors = new List<String>();

        Test.startTest();
        LoanRequestValidationService.validateBeforeUpdate(
            new List<LoanRequest__c>{ newLoan },
            new Map<Id, LoanRequest__c>{ oldLoan.Id => oldLoan },
            BankCrmTestDataFactory.buildContext(settings)
        );
        Test.stopTest();

        System.assert(
            String.join(LoanRequestValidationService.capturedTriggerErrors, '|')
                .contains('DecisionReason__c')
        );
    }
}
