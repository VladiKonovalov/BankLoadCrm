@IsTest
private class ManagerNotificationRecipientInvocableTest {
    @IsTest
    static void resolve_returnsActiveRelationshipManager() {
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(250000, null, 'Bank_CRM_Default_Manager')
        );

        ManagerNotificationRecipientInvocable.Request request =
            new ManagerNotificationRecipientInvocable.Request();
        request.customerId = customer.Id;

        Test.startTest();
        List<ManagerNotificationRecipientInvocable.Result> results =
            ManagerNotificationRecipientInvocable.resolve(
                new List<ManagerNotificationRecipientInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isResolved);
        System.assertEquals(UserInfo.getUserId(), results[0].recipientUserId);
    }

    @IsTest
    static void resolve_usernameFallback_whenNoRm() {
        Customer__c customer = BankCrmTestDataFactory.createCustomer(true);
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(250000, UserInfo.getUserName(), null)
        );

        ManagerNotificationRecipientInvocable.Request request =
            new ManagerNotificationRecipientInvocable.Request();
        request.customerId = customer.Id;

        Test.startTest();
        List<ManagerNotificationRecipientInvocable.Result> results =
            ManagerNotificationRecipientInvocable.resolve(
                new List<ManagerNotificationRecipientInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].isResolved);
        System.assertEquals(UserInfo.getUserId(), results[0].recipientUserId);
    }

    @IsTest
    static void resolve_queueOnly_isUnresolvedForNotification() {
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        UserRoutingResolver.forcedInactiveUserIds = new Set<Id>{ UserInfo.getUserId() };
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(250000, null, 'Bank_CRM_Default_Manager')
        );

        ManagerNotificationRecipientInvocable.Request request =
            new ManagerNotificationRecipientInvocable.Request();
        request.customerId = customer.Id;

        Test.startTest();
        List<ManagerNotificationRecipientInvocable.Result> results =
            ManagerNotificationRecipientInvocable.resolve(
                new List<ManagerNotificationRecipientInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].isResolved);
        System.assertEquals(null, results[0].recipientUserId);
        System.assert(
            results[0].failureReason.contains('not a User'),
            results[0].failureReason
        );
    }

    @IsTest
    static void resolve_blankCustomer_isUnresolved() {
        ManagerNotificationRecipientInvocable.Request request =
            new ManagerNotificationRecipientInvocable.Request();

        Test.startTest();
        List<ManagerNotificationRecipientInvocable.Result> results =
            ManagerNotificationRecipientInvocable.resolve(
                new List<ManagerNotificationRecipientInvocable.Request>{ request }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].isResolved);
        System.assert(results[0].failureReason.contains('Customer Id'));
    }
}
