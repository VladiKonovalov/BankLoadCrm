/**
 * Centralizes CRUD/FLS checks and inaccessible-field stripping.
 */
public with sharing class ApexSecurityHelper {
    private static final String EDIT_INTEGRATION_FIELDS_PERMISSION =
        'Edit_Bank_CRM_Integration_Fields';
    private static final String REOPEN_FINAL_LOAN_DECISION_PERMISSION =
        'Reopen_Final_Loan_Decision';

    public static void assertCreateable(Schema.SObjectType objectType) {
        if (objectType == null || !objectType.getDescribe().isCreateable()) {
            throw new BankCrmException.AuthorizationException(
                'You do not have permission to create this record.'
            );
        }
    }

    public static void assertUpdateable(Schema.SObjectType objectType) {
        if (objectType == null || !objectType.getDescribe().isUpdateable()) {
            throw new BankCrmException.AuthorizationException(
                'You do not have permission to update this record.'
            );
        }
    }

    public static void assertReadable(Schema.SObjectType objectType) {
        if (objectType == null || !objectType.getDescribe().isAccessible()) {
            throw new BankCrmException.AuthorizationException(
                'You do not have permission to read this record.'
            );
        }
    }

    public static List<SObject> stripInaccessible(
        System.AccessType accessType,
        List<SObject> records
    ) {
        if (records == null || records.isEmpty()) {
            return records;
        }
        SObjectAccessDecision decision = Security.stripInaccessible(accessType, records);
        return decision.getRecords();
    }

    public static Boolean canEditIntegrationFields() {
        return FeatureManagement.checkPermission(EDIT_INTEGRATION_FIELDS_PERMISSION);
    }

    public static Boolean canReopenFinalLoanDecision() {
        return FeatureManagement.checkPermission(REOPEN_FINAL_LOAN_DECISION_PERMISSION);
    }
}
