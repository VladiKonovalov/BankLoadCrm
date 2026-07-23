@IsTest
private class TaskRepositoryTest {
    @IsTest
    static void insertTasks_roundTrip() {
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(true);
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            300000,
            'Draft',
            true
        );

        Task taskRecord = new Task(
            Subject = 'Review High-Value Loan',
            WhatId = loan.Id,
            OwnerId = UserInfo.getUserId(),
            Status = 'Not Started',
            Priority = 'High',
            ActivityDate = Date.today().addDays(2)
        );

        Test.startTest();
        List<Database.SaveResult> results = TaskRepository.insertTasks(
            new List<Task>{ taskRecord }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isSuccess());
        Task loaded = [SELECT Subject, WhatId, Priority FROM Task WHERE Id = :results[0].getId()];
        System.assertEquals('Review High-Value Loan', loaded.Subject);
        System.assertEquals(loan.Id, loaded.WhatId);
        System.assertEquals('High', loaded.Priority);
    }

    @IsTest
    static void insertTasks_empty_returnsEmpty() {
        System.assertEquals(0, TaskRepository.insertTasks(new List<Task>()).size());
    }
}
