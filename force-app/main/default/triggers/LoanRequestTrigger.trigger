trigger LoanRequestTrigger on LoanRequest__c (
    before insert,
    before update,
    after insert,
    after update
) {
    LoanRequestTriggerHandler.run(Trigger.operationType, Trigger.new, Trigger.oldMap);
}
