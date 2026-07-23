/**
 * Isolates mandatory bulk Task insertion for high-value escalation.
 */
public with sharing class TaskRepository {
    public static List<Database.SaveResult> insertTasks(List<Task> tasks) {
        if (tasks == null || tasks.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        ApexSecurityHelper.assertCreateable(Task.SObjectType);
        List<SObject> stripped = ApexSecurityHelper.stripInaccessible(
            AccessType.CREATABLE,
            tasks
        );
        List<Task> toInsert = new List<Task>();
        for (SObject row : stripped) {
            toInsert.add((Task) row);
        }

        try {
            return Database.insert(toInsert, true);
        } catch (DmlException ex) {
            throw new BankCrmException.MandatoryAutomationException(
                'Failed to insert mandatory high-value Tasks: ' + ex.getMessage()
            );
        }
    }
}
