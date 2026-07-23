@IsTest
private class UserRoutingResolverTest {
    @IsTest
    static void resolveOwners_prefersActiveRelationshipManager() {
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(
            250000,
            'missing.user@example.invalid',
            'Bank_CRM_Default_Manager'
        );

        Test.startTest();
        Map<Id, Id> owners = UserRoutingResolver.resolveOwners(
            new Map<Id, Customer__c>{ customer.Id => customer },
            settings
        );
        Test.stopTest();

        System.assertEquals(UserInfo.getUserId(), owners.get(customer.Id));
    }

    @IsTest
    static void resolveOwners_inactiveRm_fallsBackToQueue() {
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        UserRoutingResolver.forcedInactiveUserIds = new Set<Id>{ UserInfo.getUserId() };
        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(
            250000,
            null,
            'Bank_CRM_Default_Manager'
        );

        Id queueId = resolveDefaultQueueId();
        System.assertNotEquals(null, queueId, 'Expected Bank_CRM_Default_Manager queue');

        Test.startTest();
        Map<Id, UserRoutingResolver.RoutingResult> detailed =
            UserRoutingResolver.resolveOwnersDetailed(
                new Map<Id, Customer__c>{ customer.Id => customer },
                settings
            );
        Test.stopTest();

        UserRoutingResolver.RoutingResult result = detailed.get(customer.Id);
        System.assertEquals(true, result.isSuccess());
        System.assertEquals(queueId, result.ownerId);
        System.assertEquals(true, result.usedFallback);
        System.assertEquals(true, result.relationshipManagerInactive);
    }

    @IsTest
    static void resolveOwners_usernameFallback_whenNoRm() {
        Customer__c customer = BankCrmTestDataFactory.createCustomer(true);
        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(
            250000,
            UserInfo.getUserName(),
            null
        );

        Test.startTest();
        Id ownerId = UserRoutingResolver.resolveOwner(customer, settings);
        Test.stopTest();

        System.assertEquals(UserInfo.getUserId(), ownerId);
    }

    @IsTest
    static void resolveOwners_missingUsername_throws() {
        Customer__c customer = BankCrmTestDataFactory.createCustomer(true);
        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(
            250000,
            'does.not.exist@example.invalid',
            'Bank_CRM_Default_Manager'
        );

        Boolean threw = false;
        try {
            UserRoutingResolver.resolveOwners(
                new Map<Id, Customer__c>{ customer.Id => customer },
                settings
            );
        } catch (BankCrmException.ValidationException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('username'));
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void resolveOwners_blankRmAndBlankSettings_throws() {
        Customer__c customer = BankCrmTestDataFactory.createCustomer(true);
        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(250000, null, null);

        Boolean threw = false;
        try {
            UserRoutingResolver.resolveOwner(customer, settings);
        } catch (BankCrmException.ValidationException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('No active relationship manager'));
        }
        System.assertEquals(true, threw);
    }

    private static Id resolveDefaultQueueId() {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = 'Bank_CRM_Default_Manager'
            LIMIT 1
        ];
        return queues.isEmpty() ? null : queues[0].Id;
    }
}
