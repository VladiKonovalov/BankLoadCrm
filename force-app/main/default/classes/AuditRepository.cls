/**
 * Append-only insert boundary for Audit__c. No public update/delete API.
 * Object createability is enforced; field stripping is skipped because Apex-owned
 * audits are mandatory automation and must retain LoanRequest__c even when the
 * running user lacks edit FLS on that lookup (validation requires it).
 */
public with sharing class AuditRepository {
    public static List<Database.SaveResult> insertEvents(List<Audit__c> events) {
        if (events == null || events.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        ApexSecurityHelper.assertCreateable(Audit__c.SObjectType);

        try {
            return Database.insert(events, true);
        } catch (DmlException ex) {
            throw new BankCrmException.MandatoryAutomationException(
                'Failed to insert mandatory audit events: ' + ex.getMessage()
            );
        }
    }
}
