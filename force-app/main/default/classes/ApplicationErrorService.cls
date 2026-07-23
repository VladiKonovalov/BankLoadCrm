/**
 * Normalizes operational failure capture for Apex, async jobs, and handlers.
 * Never swallows MandatoryAutomationException.
 */
public with sharing class ApplicationErrorService {
    public class ErrorContext {
        public String sourceComponent;
        public String operation;
        public Id loanRequestId;
        public Id customerId;
        public String correlationId;
        /** Optional category override; otherwise derived from exception type. */
        public String category;
        /** Optional retryability override. */
        public Boolean retryable;
        public Datetime nextRetryAt;

        public ErrorContext(String sourceComponent, String operation) {
            this.sourceComponent = sourceComponent;
            this.operation = operation;
            this.correlationId = CorrelationIdUtil.currentOrNew();
        }
    }

    /**
     * Persists a sanitized Application_Error__c and returns it (Id may be set on success).
     */
    public static Application_Error__c log(Exception e, ErrorContext ctx) {
        Application_Error__c error = buildError(e, ctx);
        List<Database.SaveResult> results = ApplicationErrorRepository.insertErrors(
            new List<Application_Error__c>{ error }
        );
        if (!results.isEmpty() && results[0].isSuccess()) {
            error.Id = results[0].getId();
        }
        return error;
    }

    /**
     * Logs then always rethrows. Mandatory automation failures are never swallowed.
     */
    public static void logAndRethrow(Exception e, ErrorContext ctx) {
        try {
            log(e, ctx);
        } catch (Exception ignore) {
            // Best-effort logging must not hide the original failure.
        }
        throw e;
    }

    /**
     * Logs non-critical failures without rethrowing.
     * MandatoryAutomationException is never treated as non-critical.
     */
    public static Application_Error__c logNonCritical(Exception e, ErrorContext ctx) {
        if (e instanceof BankCrmException.MandatoryAutomationException) {
            throw (BankCrmException.MandatoryAutomationException) e;
        }
        ErrorContext resolved = ctx == null
            ? new ErrorContext('Unknown', 'logNonCritical')
            : ctx;
        if (String.isBlank(resolved.category)) {
            resolved.category = 'Notification';
        }
        if (resolved.retryable == null) {
            resolved.retryable = true;
        }
        if (resolved.retryable == true && resolved.nextRetryAt == null) {
            resolved.nextRetryAt = System.now().addMinutes(resolveRetryDelayMinutes());
        }
        return log(e, resolved);
    }

    @TestVisible
    private static Application_Error__c buildError(Exception e, ErrorContext ctx) {
        if (e == null) {
            throw new BankCrmException.ValidationException('Exception is required for error logging.');
        }
        ErrorContext resolved = ctx == null
            ? new ErrorContext('Unknown', 'unspecified')
            : ctx;

        String category = String.isNotBlank(resolved.category)
            ? resolved.category
            : mapCategory(e);
        Boolean retryable = resolved.retryable != null
            ? resolved.retryable
            : isRetryableCategory(category);
        Datetime nextRetryAt = resolved.nextRetryAt;
        String resolutionStatus = 'Open';
        if (retryable == true) {
            if (nextRetryAt == null) {
                nextRetryAt = System.now().addMinutes(resolveRetryDelayMinutes());
            }
            resolutionStatus = 'Retry Scheduled';
        }

        String message = SanitizedMessageUtil.sanitize(
            e.getTypeName() + ': ' + e.getMessage()
        );
        if (String.isBlank(message)) {
            message = 'Unknown error';
        }

        return new Application_Error__c(
            SourceComponent__c = String.isBlank(resolved.sourceComponent)
                ? 'Unknown'
                : resolved.sourceComponent.left(120),
            Operation__c = String.isBlank(resolved.operation)
                ? 'unspecified'
                : resolved.operation.left(120),
            LoanRequest__c = resolved.loanRequestId,
            Customer__c = resolved.customerId,
            CorrelationId__c = String.isBlank(resolved.correlationId)
                ? CorrelationIdUtil.currentOrNew()
                : resolved.correlationId.left(64),
            OccurredAt__c = System.now(),
            Category__c = category,
            IsRetryable__c = retryable,
            AttemptCount__c = 0,
            NextRetryAt__c = nextRetryAt,
            SanitizedMessage__c = message,
            StackFingerprint__c = fingerprint(e),
            ResolutionStatus__c = resolutionStatus
        );
    }

    private static String mapCategory(Exception e) {
        if (e instanceof BankCrmException.ValidationException) {
            return 'Validation';
        }
        if (e instanceof BankCrmException.AuthorizationException) {
            return 'Authorization';
        }
        if (e instanceof BankCrmException.MandatoryAutomationException) {
            return 'Automation';
        }
        if (e instanceof BankCrmException.IntegrationException) {
            return 'Integration Permanent';
        }
        String typeName = e.getTypeName();
        if (typeName != null && typeName.toLowerCase().contains('email')) {
            return 'Notification';
        }
        return 'Unknown';
    }

    private static Boolean isRetryableCategory(String category) {
        return category == 'Notification'
            || category == 'Integration Transient'
            || category == 'Flow Fault';
    }

    private static Integer resolveRetryDelayMinutes() {
        try {
            BankCrmSettings settings = BankCrmSettingsProvider.getSettings();
            if (settings != null && settings.retryBaseDelayMinutes != null && settings.retryBaseDelayMinutes > 0) {
                return settings.retryBaseDelayMinutes;
            }
        } catch (Exception ignore) {
            // Fall through to safe default when settings are unavailable.
        }
        return 15;
    }

    private static String fingerprint(Exception e) {
        String raw = e.getTypeName() + '|' + String.valueOf(e.getMessage());
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(raw));
        return EncodingUtil.convertToHex(digest);
    }
}
