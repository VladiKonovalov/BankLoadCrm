@IsTest
private class ApplicationErrorServiceTest {
    @IsTest
    static void log_persistsSanitizedError() {
        BankCrmSettingsProvider.setTestOverride(BankCrmTestDataFactory.buildSettings(250000));
        ApplicationErrorService.ErrorContext ctx =
            new ApplicationErrorService.ErrorContext('UnitTest', 'log');
        ctx.correlationId = 'corr-log-1';

        Test.startTest();
        Application_Error__c error = ApplicationErrorService.log(
            new BankCrmException.ValidationException('password=secret123 failed'),
            ctx
        );
        Test.stopTest();

        System.assertNotEquals(null, error.Id);
        Application_Error__c loaded = [
            SELECT
                Category__c,
                SanitizedMessage__c,
                IsRetryable__c,
                ResolutionStatus__c,
                CorrelationId__c,
                StackFingerprint__c
            FROM Application_Error__c
            WHERE Id = :error.Id
        ];
        System.assertEquals('Validation', loaded.Category__c);
        System.assertEquals(false, loaded.IsRetryable__c);
        System.assertEquals('Open', loaded.ResolutionStatus__c);
        System.assertEquals('corr-log-1', loaded.CorrelationId__c);
        System.assertNotEquals(null, loaded.StackFingerprint__c);
        System.assert(
            loaded.SanitizedMessage__c.contains('[REDACTED]')
                || !loaded.SanitizedMessage__c.contains('secret123'),
            'Message should be sanitized'
        );
    }

    @IsTest
    static void logNonCritical_schedulesRetry_andDoesNotThrow() {
        BankCrmSettingsProvider.setTestOverride(BankCrmTestDataFactory.buildSettings(250000));
        ApplicationErrorService.ErrorContext ctx =
            new ApplicationErrorService.ErrorContext('CustomerEmailService', 'send');
        ctx.correlationId = 'corr-noncrit-1';

        Test.startTest();
        Application_Error__c error = ApplicationErrorService.logNonCritical(
            new BankCrmException('Delivery failed'),
            ctx
        );
        Test.stopTest();

        Application_Error__c loaded = [
            SELECT Category__c, IsRetryable__c, ResolutionStatus__c, NextRetryAt__c
            FROM Application_Error__c
            WHERE Id = :error.Id
        ];
        System.assertEquals('Notification', loaded.Category__c);
        System.assertEquals(true, loaded.IsRetryable__c);
        System.assertEquals('Retry Scheduled', loaded.ResolutionStatus__c);
        System.assertNotEquals(null, loaded.NextRetryAt__c);
    }

    @IsTest
    static void logNonCritical_mandatory_rethrows() {
        ApplicationErrorService.ErrorContext ctx =
            new ApplicationErrorService.ErrorContext('AuditService', 'commit');
        Boolean thrown = false;
        try {
            ApplicationErrorService.logNonCritical(
                new BankCrmException.MandatoryAutomationException('Audit DML failed'),
                ctx
            );
        } catch (BankCrmException.MandatoryAutomationException ex) {
            thrown = true;
            System.assert(ex.getMessage().contains('Audit DML failed'));
        }
        System.assertEquals(true, thrown);
    }

    @IsTest
    static void logAndRethrow_logsThenRethrows() {
        BankCrmSettingsProvider.setTestOverride(BankCrmTestDataFactory.buildSettings(250000));
        ApplicationErrorService.ErrorContext ctx =
            new ApplicationErrorService.ErrorContext('LoanRequestTriggerHandler', 'AFTER_UPDATE');
        ctx.correlationId = 'corr-rethrow-1';

        Boolean thrown = false;
        try {
            ApplicationErrorService.logAndRethrow(
                new BankCrmException.AuthorizationException('Access denied'),
                ctx
            );
        } catch (BankCrmException.AuthorizationException ex) {
            thrown = true;
        }
        System.assertEquals(true, thrown);

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Application_Error__c
                WHERE CorrelationId__c = 'corr-rethrow-1' AND Category__c = 'Authorization'
            ]
        );
    }

    @IsTest
    static void mapCategory_integrationAndUnknown() {
        Application_Error__c integrationError = ApplicationErrorService.log(
            new BankCrmException.IntegrationException('Permanent failure'),
            new ApplicationErrorService.ErrorContext('Orchestrator', 'callback')
        );
        Application_Error__c unknownError = ApplicationErrorService.log(
            new BankCrmException('Unexpected platform fault'),
            new ApplicationErrorService.ErrorContext('Unknown', 'npe')
        );

        System.assertEquals(
            'Integration Permanent',
            [SELECT Category__c FROM Application_Error__c WHERE Id = :integrationError.Id].Category__c
        );
        System.assertEquals(
            'Unknown',
            [SELECT Category__c FROM Application_Error__c WHERE Id = :unknownError.Id].Category__c
        );
    }
}
