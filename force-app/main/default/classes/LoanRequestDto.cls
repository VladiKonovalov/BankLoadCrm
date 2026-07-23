/**
 * Restricted LWC transfer object for loan save/read (no sensitive fields).
 */
public with sharing class LoanRequestDto {
    @AuraEnabled
    public Id id { get; set; }

    @AuraEnabled
    public Id customerId { get; set; }

    @AuraEnabled
    public String customerName { get; set; }

    @AuraEnabled
    public Decimal loanAmount { get; set; }

    @AuraEnabled
    public String loanStatus { get; set; }

    public static LoanRequestDto fromSObject(LoanRequest__c record) {
        if (record == null) {
            return null;
        }
        LoanRequestDto dto = new LoanRequestDto();
        dto.id = record.Id;
        dto.customerId = record.Customer__c;
        dto.loanAmount = record.LoanAmount__c;
        dto.loanStatus = record.LoanStatus__c;
        if (record.Customer__r != null) {
            dto.customerName = record.Customer__r.Name;
        }
        return dto;
    }

    public LoanRequest__c toSObject() {
        LoanRequest__c record = new LoanRequest__c();
        if (id != null) {
            record.Id = id;
        }
        record.Customer__c = customerId;
        record.LoanAmount__c = loanAmount;
        record.LoanStatus__c = loanStatus;
        return record;
    }
}
