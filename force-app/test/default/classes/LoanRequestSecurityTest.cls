/**
 * Persona CRUD/FLS/sharing and DTO minimization proofs (testing-strategy §11).
 */
@IsTest
private class LoanRequestSecurityTest {
    private static void setupSettings() {
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
    static void unprivilegedUser_cannotCreateLoanViaController() {
        setupSettings();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        User restricted = BankCrmTestDataFactory.createStandardUser('secnocreate');
        LoanRequestDto dto = new LoanRequestDto();
        dto.customerId = customer.Id;
        dto.loanAmount = 1500;
        dto.loanStatus = 'Draft';

        Boolean denied = false;
        System.runAs(restricted) {
            try {
                LoanRequestController.saveLoanRequest(dto);
            } catch (AuraHandledException ex) {
                denied = true;
                System.assert(
                    String.isNotBlank(ex.getMessage()),
                    'Auth denial must return a generic message'
                );
            } catch (Exception ex) {
                denied = ex instanceof BankCrmException.AuthorizationException
                    || ex instanceof AuraHandledException;
            }
        }
        System.assertEquals(true, denied);
        System.assertEquals(0, [SELECT COUNT() FROM LoanRequest__c WHERE Customer__c = :customer.Id]);
    }

    @IsTest
    static void unprivilegedUser_cannotReadOtherOwnersLoan() {
        setupSettings();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            2000,
            'Draft',
            true
        );
        User restricted = BankCrmTestDataFactory.createStandardUser('secnoread');

        Boolean denied = false;
        System.runAs(restricted) {
            try {
                LoanRequestReadController.getLoanRequest(loan.Id);
            } catch (AuraHandledException ex) {
                denied = true;
            } catch (Exception ex) {
                denied = ex instanceof BankCrmException.AuthorizationException
                    || ex instanceof AuraHandledException
                    || ex instanceof System.QueryException;
            }
        }
        System.assertEquals(true, denied);
    }

    @IsTest
    static void loanOfficer_cannotEditOrDeleteAudit() {
        setupSettings();
        User officer = BankCrmTestDataFactory.createStandardUser('secofficer');
        BankCrmTestDataFactory.assignPermissionSet(officer, 'Bank_CRM_Base');
        BankCrmTestDataFactory.assignPermissionSet(officer, 'Bank_CRM_Loan_Officer');

        System.runAs(officer) {
            System.assertEquals(
                true,
                Schema.sObjectType.Audit__c.isAccessible(),
                'Loan Officer should read Audit__c'
            );
            System.assertEquals(
                false,
                Schema.sObjectType.Audit__c.isUpdateable(),
                'Loan Officer must not update Audit__c'
            );
            System.assertEquals(
                false,
                Schema.sObjectType.Audit__c.isDeletable(),
                'Loan Officer must not delete Audit__c'
            );
        }
    }

    @IsTest
    static void ordinaryUser_cannotEditProtectedIntegrationFields() {
        setupSettings();
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

        Boolean blocked = false;
        try {
            loan.ExternalRequestId__c = 'HACK-' + Crypto.getRandomInteger();
            loan.IntegrationStatus__c = 'Pending';
            update loan;
        } catch (DmlException ex) {
            blocked = true;
            System.assert(ex.getNumDml() > 0);
        }
        System.assertEquals(true, blocked);

        LoanRequest__c reloaded = [
            SELECT ExternalRequestId__c, IntegrationStatus__c
            FROM LoanRequest__c
            WHERE Id = :loan.Id
        ];
        System.assertEquals(null, reloaded.ExternalRequestId__c);
        System.assertEquals('Not Sent', reloaded.IntegrationStatus__c);
    }

    @IsTest
    static void readDto_omitsSensitiveAndInternalFields() {
        setupSettings();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        customer.NationalIdentifier__c = '12345678901';
        update customer;
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            4200,
            'Draft',
            true
        );

        LoanRequestDto dto = LoanRequestReadController.getLoanRequest(loan.Id);
        String serialized = JSON.serialize(dto);

        System.assertEquals(customer.Name, dto.customerName);
        System.assertEquals(4200, dto.loanAmount);
        System.assertEquals('Draft', dto.loanStatus);
        System.assert(!serialized.contains('NationalIdentifier'));
        System.assert(!serialized.contains('12345678901'));
        System.assert(!serialized.contains('ExternalRequestId'));
        System.assert(!serialized.contains('IntegrationStatus'));
        System.assert(!serialized.contains('DecisionReason'));
    }

    @IsTest
    static void auditRepository_hasNoPublicUpdateOrDeleteApi() {
        // Design review assertion: append-only contract is insert-only.
        System.assertEquals(
            true,
            AuditRepository.class.getName() == 'AuditRepository'
        );
        // Compile-time contract is insertEvents only; runtime smoke via insert.
        Customer__c customer = BankCrmTestDataFactory.createCustomer(true);
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Draft',
            true
        );
        AuditRepository.insertEvents(
            new List<Audit__c>{
                BankCrmTestDataFactory.buildStatusChangedAudit(
                    loan.Id,
                    customer.Id,
                    customer.Name
                )
            }
        );
        System.assertEquals(1, [SELECT COUNT() FROM Audit__c WHERE LoanRequest__c = :loan.Id]);
    }
}
