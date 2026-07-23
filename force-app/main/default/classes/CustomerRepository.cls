/**
 * Bulk-loads customer fields needed for validation, routing, email, and DTO mapping.
 */
public with sharing class CustomerRepository {
    /**
     * Lightweight customer fields for approval email and Task routing.
     */
    public class EmailRoutingData {
        public Id customerId;
        public String name;
        public String email;
        public Id relationshipManagerId;
        public Boolean isActive;
        public String status;

        public EmailRoutingData(Customer__c customer) {
            this.customerId = customer.Id;
            this.name = customer.Name;
            this.email = customer.Email__c;
            this.relationshipManagerId = customer.RelationshipManager__c;
            this.isActive = customer.IsActive__c;
            this.status = customer.Status__c;
        }
    }

    public static List<Customer__c> getByIds(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<Customer__c>();
        }
        ApexSecurityHelper.assertReadable(Customer__c.SObjectType);
        return [
            SELECT
                Id,
                Name,
                CustomerNumber__c,
                Email__c,
                Status__c,
                IsActive__c,
                RelationshipManager__c,
                RelationshipManager__r.IsActive
            FROM Customer__c
            WHERE Id IN :ids
        ];
    }

    public static Map<Id, Customer__c> getMapByIds(Set<Id> ids) {
        return new Map<Id, Customer__c>(getByIds(ids));
    }

    public static Map<Id, EmailRoutingData> getEmailRoutingData(Set<Id> ids) {
        Map<Id, EmailRoutingData> result = new Map<Id, EmailRoutingData>();
        for (Customer__c customer : getByIds(ids)) {
            result.put(customer.Id, new EmailRoutingData(customer));
        }
        return result;
    }
}
