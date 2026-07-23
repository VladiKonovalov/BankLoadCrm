/**
 * Negative validation, terminal protection, and incomplete-input paths (Part E).
 */
@IsTest
private class LoanRequestNegativeTest {
    private static void enableAutomation() {
        BankCrmTestDataFactory.enableTrigger();
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(
                250000,
                null,
                'Bank_CRM_Default_Manager'
            )
        );
    }

    @IsTest
    static void insert_nullCustomer_fails() {
        enableAutomation();
        LoanRequest__c loan = new LoanRequest__c(
            LoanAmount__c = 1000,
            LoanStatus__c = 'Draft',
            IntegrationStatus__c = 'Not Sent'
        );
        Boolean failed = false;
        try {
            insert loan;
        } catch (DmlException ex) {
            failed = true;
        }
        System.assertEquals(true, failed);
    }

    @IsTest
    static void insert_nonPositiveAmount_fails() {
        enableAutomation();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        Boolean zeroFailed = false;
        Boolean negativeFailed = false;
        try {
            insert BankCrmTestDataFactory.buildLoanRequest(customer.Id, 0, 'Draft');
        } catch (DmlException ex) {
            zeroFailed = true;
        }
        try {
            insert BankCrmTestDataFactory.buildLoanRequest(customer.Id, -5, 'Draft');
        } catch (DmlException ex) {
            negativeFailed = true;
        }
        System.assertEquals(true, zeroFailed);
        System.assertEquals(true, negativeFailed);
    }

    @IsTest
    static void update_illegalTransitions_fail() {
        enableAutomation();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c draft = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Draft',
            true
        );
        LoanRequest__c approved = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Draft',
            true
        );
        approved.LoanStatus__c = 'Submitted';
        approved.SubmissionDate__c = System.now();
        update approved;
        approved.LoanStatus__c = 'Approved';
        update approved;

        Boolean draftToApprovedFailed = false;
        Boolean approvedToDraftFailed = false;
        try {
            draft.LoanStatus__c = 'Approved';
            draft.SubmissionDate__c = System.now();
            update draft;
        } catch (DmlException ex) {
            draftToApprovedFailed = true;
        }
        try {
            approved.LoanStatus__c = 'Draft';
            update approved;
        } catch (DmlException ex) {
            approvedToDraftFailed = true;
        }
        System.assertEquals(true, draftToApprovedFailed);
        System.assertEquals(true, approvedToDraftFailed);
    }

    @IsTest
    static void update_terminalReopen_failsForOrdinaryUser() {
        enableAutomation();
        System.assertEquals(
            false,
            ApexSecurityHelper.canReopenFinalLoanDecision(),
            'Test runner must not hold Reopen_Final_Loan_Decision'
        );
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
        loan.LoanStatus__c = 'Submitted';
        loan.SubmissionDate__c = System.now();
        update loan;
        loan.LoanStatus__c = 'Rejected';
        loan.DecisionReason__c = 'Insufficient documentation';
        update loan;

        Boolean failed = false;
        try {
            loan.LoanStatus__c = 'Submitted';
            update loan;
        } catch (DmlException ex) {
            failed = true;
        }
        System.assertEquals(true, failed);
        System.assertEquals(
            'Rejected',
            [SELECT LoanStatus__c FROM LoanRequest__c WHERE Id = :loan.Id].LoanStatus__c
        );
    }

    @IsTest
    static void insert_submittedInactiveCustomer_fails() {
        enableAutomation();
        Customer__c inactive = BankCrmTestDataFactory.createInactiveCustomer(true);
        Boolean failed = false;
        try {
            insert BankCrmTestDataFactory.buildLoanRequest(inactive.Id, 2000, 'Submitted');
        } catch (DmlException ex) {
            failed = true;
        }
        System.assertEquals(true, failed);
    }

    @IsTest
    static void insert_submittedMissingEmail_fails() {
        enableAutomation();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            false
        );
        customer.Email__c = null;
        insert customer;

        Boolean failed = false;
        try {
            insert BankCrmTestDataFactory.buildLoanRequest(customer.Id, 2000, 'Submitted');
        } catch (DmlException ex) {
            failed = true;
        }
        System.assertEquals(true, failed);
    }

    @IsTest
    static void reject_withoutDecisionReason_fails() {
        enableAutomation();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Submitted',
            true
        );

        Boolean failed = false;
        try {
            loan.LoanStatus__c = 'Rejected';
            update loan;
        } catch (DmlException ex) {
            failed = true;
        }
        System.assertEquals(true, failed);
    }

    @IsTest
    static void exactThreshold_notHighValue_noTask() {
        enableAutomation();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );

        Test.startTest();
        LoanRequest__c loan = BankCrmTestDataFactory.createBelowThresholdLoan(
            customer.Id,
            250000,
            true
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :loan.Id]);
        System.assertEquals(
            false,
            [
                SELECT HighValueTaskCreated__c
                FROM LoanRequest__c
                WHERE Id = :loan.Id
            ]
            .HighValueTaskCreated__c
        );
    }

    @IsTest
    static void lwcSave_incompleteAndInvalid_returnsFailures_noInsert() {
        enableAutomation();
        Integer beforeCount = [SELECT COUNT() FROM LoanRequest__c];

        LoanRequestDto incomplete = new LoanRequestDto();
        incomplete.loanAmount = -1;
        incomplete.loanStatus = 'Under Review';

        SaveResultDto result = LoanRequestController.saveLoanRequest(incomplete);
        System.assertEquals(false, result.success);
        System.assertEquals(null, result.loanRequestId);
        System.assert(result.errors.size() >= 2);
        System.assertEquals(beforeCount, [SELECT COUNT() FROM LoanRequest__c]);

        Customer__c inactive = BankCrmTestDataFactory.createInactiveCustomer(true);
        LoanRequestDto submittedInactive = new LoanRequestDto();
        submittedInactive.customerId = inactive.Id;
        submittedInactive.loanAmount = 5000;
        submittedInactive.loanStatus = 'Submitted';

        SaveResultDto inactiveResult = LoanRequestController.saveLoanRequest(submittedInactive);
        System.assertEquals(false, inactiveResult.success);
        System.assertEquals(null, inactiveResult.loanRequestId);
    }

    @IsTest
    static void amountOnlyUpdate_doesNotCreateStatusChangedAudit() {
        enableAutomation();
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

        Test.startTest();
        loan.LoanAmount__c = 1500;
        update loan;
        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Audit__c
                WHERE LoanRequest__c = :loan.Id AND EventType__c = 'STATUS_CHANGED'
            ]
        );
    }
}
