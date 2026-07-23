/**
 * Collects prepared Task side effects and HighValueTaskCreated__c marker updates
 * before one bulk commit.
 */
public with sharing class TaskPlan {
    private final List<Task> tasks = new List<Task>();
    private final Set<Id> markerSetLoanIds = new Set<Id>();
    private final Set<Id> markerResetLoanIds = new Set<Id>();

    public void add(Task taskRecord, Id loanRequestId) {
        if (taskRecord == null) {
            return;
        }
        tasks.add(taskRecord);
        if (loanRequestId != null) {
            markerSetLoanIds.add(loanRequestId);
        }
    }

    public void addMarkerReset(Id loanRequestId) {
        if (loanRequestId != null) {
            markerResetLoanIds.add(loanRequestId);
        }
    }

    public Boolean isEmpty() {
        return tasks.isEmpty() && markerSetLoanIds.isEmpty() && markerResetLoanIds.isEmpty();
    }

    public List<Task> getTasks() {
        return new List<Task>(tasks);
    }

    public Set<Id> getLoanRequestIds() {
        return new Set<Id>(markerSetLoanIds);
    }

    public Set<Id> getMarkerResetLoanIds() {
        return new Set<Id>(markerResetLoanIds);
    }

    public Integer size() {
        return tasks.size();
    }
}
