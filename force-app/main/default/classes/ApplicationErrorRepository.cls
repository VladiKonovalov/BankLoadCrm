/**
 * Persists Application_Error__c lifecycle data and retrieves due retries.
 * Uses without sharing so operational logging can succeed even when the
 * running user lacks broad object FLS; payloads must still be sanitized by callers.
 */
public without sharing class ApplicationErrorRepository {
    public static List<Database.SaveResult> insertErrors(List<Application_Error__c> errors) {
        if (errors == null || errors.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        return Database.insert(errors, false);
    }

    public static List<Database.SaveResult> updateErrors(List<Application_Error__c> errors) {
        if (errors == null || errors.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        return Database.update(errors, false);
    }

    public static List<Application_Error__c> findDueRetries(Datetime asOf, Integer limitSize) {
        Datetime dueAsOf = asOf == null ? System.now() : asOf;
        Integer resolvedLimit = limitSize == null || limitSize <= 0 ? 200 : limitSize;
        return [
            SELECT
                Id,
                Name,
                SourceComponent__c,
                Operation__c,
                LoanRequest__c,
                Customer__c,
                CorrelationId__c,
                OccurredAt__c,
                Category__c,
                IsRetryable__c,
                AttemptCount__c,
                NextRetryAt__c,
                SanitizedMessage__c,
                StackFingerprint__c,
                ResolutionStatus__c,
                OwnerId,
                ResolvedAt__c
            FROM Application_Error__c
            WHERE IsRetryable__c = TRUE
                AND ResolutionStatus__c = 'Retry Scheduled'
                AND NextRetryAt__c <= :dueAsOf
            ORDER BY NextRetryAt__c ASC
            LIMIT :resolvedLimit
        ];
    }
}
