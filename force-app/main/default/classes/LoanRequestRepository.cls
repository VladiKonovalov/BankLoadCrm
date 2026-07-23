/**
 * Persist and retrieve LoanRequest__c with CRUD/FLS-aware boundaries.
 */
public with sharing class LoanRequestRepository {
    /**
     * Options for repository DML. Defaults are all-or-none with security enforcement.
     */
    public class DmlOptions {
        public Boolean allOrNone = true;
        public Boolean enforceSecurity = true;
    }

    /**
     * Criteria for reconciliation / integration candidate queries.
     */
    public class IntegrationQueryCriteria {
        public Set<String> statuses;
        public Datetime olderThanOrEqual;
        public Datetime newerThan;
        public Integer limitSize;

        public IntegrationQueryCriteria() {
            this.statuses = new Set<String>{ 'Pending', 'Retry Pending' };
            this.limitSize = 200;
        }
    }

    public static List<Database.SaveResult> insertLoans(
        List<LoanRequest__c> records,
        DmlOptions options
    ) {
        if (records == null || records.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        DmlOptions resolved = resolveOptions(options);
        ApexSecurityHelper.assertCreateable(LoanRequest__c.SObjectType);
        List<LoanRequest__c> toInsert = prepareForWrite(records, AccessType.CREATABLE, resolved);
        return Database.insert(toInsert, resolved.allOrNone);
    }

    public static List<Database.SaveResult> updateLoans(
        List<LoanRequest__c> records,
        DmlOptions options
    ) {
        if (records == null || records.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        DmlOptions resolved = resolveOptions(options);
        ApexSecurityHelper.assertUpdateable(LoanRequest__c.SObjectType);
        List<LoanRequest__c> toUpdate = prepareForWrite(records, AccessType.UPDATABLE, resolved);
        return Database.update(toUpdate, resolved.allOrNone);
    }

    public static List<LoanRequest__c> getByIds(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<LoanRequest__c>();
        }
        ApexSecurityHelper.assertReadable(LoanRequest__c.SObjectType);
        return [
            SELECT
                Id,
                Name,
                Customer__c,
                Customer__r.Name,
                Customer__r.CustomerNumber__c,
                LoanAmount__c,
                LoanStatus__c,
                SubmissionDate__c,
                ExternalRequestId__c,
                ExternalDecisionReference__c,
                IntegrationStatus__c,
                IntegrationLastAttempt__c,
                HighValueTaskCreated__c,
                DecisionReason__c,
                OwnerId,
                CreatedDate,
                LastModifiedDate
            FROM LoanRequest__c
            WHERE Id IN :ids
        ];
    }

    public static Map<Id, LoanRequest__c> getMapByIds(Set<Id> ids) {
        return new Map<Id, LoanRequest__c>(getByIds(ids));
    }

    public static List<LoanRequest__c> getByExternalRequestIds(Set<String> keys) {
        if (keys == null || keys.isEmpty()) {
            return new List<LoanRequest__c>();
        }
        ApexSecurityHelper.assertReadable(LoanRequest__c.SObjectType);
        return [
            SELECT
                Id,
                Name,
                Customer__c,
                LoanAmount__c,
                LoanStatus__c,
                ExternalRequestId__c,
                ExternalDecisionReference__c,
                IntegrationStatus__c,
                IntegrationLastAttempt__c,
                HighValueTaskCreated__c,
                DecisionReason__c
            FROM LoanRequest__c
            WHERE ExternalRequestId__c IN :keys
        ];
    }

    public static Map<String, LoanRequest__c> getMapByExternalRequestIds(Set<String> keys) {
        Map<String, LoanRequest__c> byKey = new Map<String, LoanRequest__c>();
        for (LoanRequest__c loan : getByExternalRequestIds(keys)) {
            if (String.isNotBlank(loan.ExternalRequestId__c)) {
                byKey.put(loan.ExternalRequestId__c, loan);
            }
        }
        return byKey;
    }

    /**
     * Stubbed selective query for later reconciliation batch use.
     * Filters by integration status and optional aging window on IntegrationLastAttempt__c.
     */
    public static List<LoanRequest__c> findIntegrationCandidates(IntegrationQueryCriteria criteria) {
        if (criteria == null) {
            criteria = new IntegrationQueryCriteria();
        }
        Set<String> statuses = criteria.statuses == null || criteria.statuses.isEmpty()
            ? new Set<String>{ 'Pending', 'Retry Pending' }
            : criteria.statuses;
        Integer limitSize = criteria.limitSize == null || criteria.limitSize <= 0
            ? 200
            : criteria.limitSize;

        ApexSecurityHelper.assertReadable(LoanRequest__c.SObjectType);

        if (criteria.olderThanOrEqual != null && criteria.newerThan != null) {
            return [
                SELECT
                    Id,
                    Name,
                    Customer__c,
                    LoanAmount__c,
                    LoanStatus__c,
                    ExternalRequestId__c,
                    IntegrationStatus__c,
                    IntegrationLastAttempt__c
                FROM LoanRequest__c
                WHERE IntegrationStatus__c IN :statuses
                    AND IntegrationLastAttempt__c <= :criteria.olderThanOrEqual
                    AND IntegrationLastAttempt__c >= :criteria.newerThan
                ORDER BY IntegrationLastAttempt__c ASC NULLS LAST
                LIMIT :limitSize
            ];
        }
        if (criteria.olderThanOrEqual != null) {
            return [
                SELECT
                    Id,
                    Name,
                    Customer__c,
                    LoanAmount__c,
                    LoanStatus__c,
                    ExternalRequestId__c,
                    IntegrationStatus__c,
                    IntegrationLastAttempt__c
                FROM LoanRequest__c
                WHERE IntegrationStatus__c IN :statuses
                    AND IntegrationLastAttempt__c <= :criteria.olderThanOrEqual
                ORDER BY IntegrationLastAttempt__c ASC NULLS LAST
                LIMIT :limitSize
            ];
        }
        return [
            SELECT
                Id,
                Name,
                Customer__c,
                LoanAmount__c,
                LoanStatus__c,
                ExternalRequestId__c,
                IntegrationStatus__c,
                IntegrationLastAttempt__c
            FROM LoanRequest__c
            WHERE IntegrationStatus__c IN :statuses
            ORDER BY IntegrationLastAttempt__c ASC NULLS LAST
            LIMIT :limitSize
        ];
    }

    private static DmlOptions resolveOptions(DmlOptions options) {
        return options == null ? new DmlOptions() : options;
    }

    private static List<LoanRequest__c> prepareForWrite(
        List<LoanRequest__c> records,
        AccessType accessType,
        DmlOptions options
    ) {
        if (options.enforceSecurity != true) {
            return records;
        }
        List<SObject> stripped = ApexSecurityHelper.stripInaccessible(accessType, records);
        List<LoanRequest__c> typed = new List<LoanRequest__c>();
        for (SObject row : stripped) {
            typed.add((LoanRequest__c) row);
        }
        return typed;
    }
}
