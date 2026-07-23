@IsTest
private class CustomerRepositoryTest {
    @IsTest
    static void getByIds_returnsRoutingFields() {
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );

        Test.startTest();
        List<Customer__c> loaded = CustomerRepository.getByIds(new Set<Id>{ customer.Id });
        Map<Id, Customer__c> byId = CustomerRepository.getMapByIds(
            new Set<Id>{ customer.Id }
        );
        Test.stopTest();

        System.assertEquals(1, loaded.size());
        System.assertEquals(customer.Name, loaded[0].Name);
        System.assertEquals(customer.Email__c, loaded[0].Email__c);
        System.assertEquals(UserInfo.getUserId(), loaded[0].RelationshipManager__c);
        System.assertEquals(customer.Id, byId.get(customer.Id).Id);
    }

    @IsTest
    static void getEmailRoutingData_mapsLightweightDto() {
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );

        Test.startTest();
        Map<Id, CustomerRepository.EmailRoutingData> routing =
            CustomerRepository.getEmailRoutingData(new Set<Id>{ customer.Id });
        Test.stopTest();

        System.assertEquals(1, routing.size());
        CustomerRepository.EmailRoutingData data = routing.get(customer.Id);
        System.assertEquals(customer.Id, data.customerId);
        System.assertEquals(customer.Name, data.name);
        System.assertEquals(customer.Email__c, data.email);
        System.assertEquals(UserInfo.getUserId(), data.relationshipManagerId);
        System.assertEquals(true, data.isActive);
    }

    @IsTest
    static void getByIds_emptySet_returnsEmpty() {
        System.assertEquals(0, CustomerRepository.getByIds(new Set<Id>()).size());
        System.assertEquals(
            0,
            CustomerRepository.getEmailRoutingData(new Set<Id>()).size()
        );
    }
}
