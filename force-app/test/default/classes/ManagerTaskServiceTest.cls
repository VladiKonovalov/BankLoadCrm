@IsTest
private class ManagerTaskServiceTest {
    private static void isolateFromTrigger() {
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(250000)
        );
    }

    @IsTest
    static void insertAboveThreshold_createsTaskAndSetsMarker() {
        isolateFromTrigger();
        Decimal threshold = 250000;
        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(
            threshold,
            null,
            'Bank_CRM_Default_Manager'
        );
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createHighValueLoan(
            customer.Id,
            threshold,
            true
        );
        LoanRequestChange change = LoanRequestChange.fromTrigger(loan, null);

        Test.startTest();
        TaskPlan plan = ManagerTaskService.planHighValueTasks(
            new List<LoanRequestChange>{ change },
            settings
        );
        ManagerTaskService.commitTasks(plan);
        Test.stopTest();

        System.assertEquals(1, plan.size());
        List<Task> tasks = [
            SELECT Subject, WhatId, Priority, OwnerId, ActivityDate
            FROM Task
            WHERE WhatId = :loan.Id
        ];
        System.assertEquals(1, tasks.size());
        System.assertEquals('High', tasks[0].Priority);
        System.assertEquals(UserInfo.getUserId(), tasks[0].OwnerId);
        System.assertEquals(Date.today().addDays(2), tasks[0].ActivityDate);

        LoanRequest__c reloaded = [
            SELECT HighValueTaskCreated__c
            FROM LoanRequest__c
            WHERE Id = :loan.Id
        ];
        System.assertEquals(true, reloaded.HighValueTaskCreated__c);
    }

    @IsTest
    static void exactThreshold_doesNotCreateTask() {
        isolateFromTrigger();
        Decimal threshold = 250000;
        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(threshold);
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createBelowThresholdLoan(
            customer.Id,
            threshold,
            true
        );
        LoanRequestChange change = LoanRequestChange.fromTrigger(loan, null);

        TaskPlan plan = ManagerTaskService.planHighValueTasks(
            new List<LoanRequestChange>{ change },
            settings
        );
        System.assertEquals(true, plan.isEmpty());
        System.assertEquals(0, plan.size());
    }

    @IsTest
    static void crossingUpdate_createsTask_secondUpdateStillAbove_doesNot() {
        isolateFromTrigger();
        Decimal threshold = 250000;
        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(threshold);
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c oldLoan = BankCrmTestDataFactory.createBelowThresholdLoan(
            customer.Id,
            threshold,
            true
        );
        LoanRequest__c newLoan = oldLoan.clone(true, true, true, true);
        newLoan.LoanAmount__c = threshold + 5000;

        TaskPlan firstPlan = ManagerTaskService.planHighValueTasks(
            new List<LoanRequestChange>{ LoanRequestChange.fromTrigger(newLoan, oldLoan) },
            settings
        );
        ManagerTaskService.commitTasks(firstPlan);
        System.assertEquals(1, firstPlan.size());

        LoanRequest__c afterFirst = [
            SELECT Id, Customer__c, LoanAmount__c, LoanStatus__c, HighValueTaskCreated__c,
                IntegrationStatus__c, ExternalRequestId__c
            FROM LoanRequest__c
            WHERE Id = :oldLoan.Id
        ];
        LoanRequest__c stillAbove = afterFirst.clone(true, true, true, true);
        stillAbove.LoanAmount__c = threshold + 9000;

        TaskPlan secondPlan = ManagerTaskService.planHighValueTasks(
            new List<LoanRequestChange>{
                LoanRequestChange.fromTrigger(stillAbove, afterFirst)
            },
            settings
        );
        System.assertEquals(true, secondPlan.isEmpty());
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Task WHERE WhatId = :oldLoan.Id]
        );
    }

    @IsTest
    static void lowerThenRaise_createsNewTask() {
        isolateFromTrigger();
        Decimal threshold = 250000;
        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(threshold);
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createHighValueLoan(
            customer.Id,
            threshold,
            true
        );
        ManagerTaskService.commitTasks(
            ManagerTaskService.planHighValueTasks(
                new List<LoanRequestChange>{ LoanRequestChange.fromTrigger(loan, null) },
                settings
            )
        );

        LoanRequest__c above = [
            SELECT Id, Customer__c, LoanAmount__c, LoanStatus__c, HighValueTaskCreated__c,
                IntegrationStatus__c, ExternalRequestId__c
            FROM LoanRequest__c
            WHERE Id = :loan.Id
        ];
        LoanRequest__c below = above.clone(true, true, true, true);
        below.LoanAmount__c = threshold;
        // Persist the drop so the re-cross old amount is at/below threshold in DB.
        update below;

        TaskPlan resetPlan = ManagerTaskService.planHighValueTasks(
            new List<LoanRequestChange>{ LoanRequestChange.fromTrigger(below, above) },
            settings
        );
        ManagerTaskService.commitTasks(resetPlan);
        System.assertEquals(1, resetPlan.getMarkerResetLoanIds().size());

        LoanRequest__c resetLoan = [
            SELECT Id, Customer__c, LoanAmount__c, LoanStatus__c, HighValueTaskCreated__c,
                IntegrationStatus__c, ExternalRequestId__c
            FROM LoanRequest__c
            WHERE Id = :loan.Id
        ];
        System.assertEquals(false, resetLoan.HighValueTaskCreated__c);
        System.assertEquals(threshold, resetLoan.LoanAmount__c);

        LoanRequest__c raised = resetLoan.clone(true, true, true, true);
        raised.LoanAmount__c = threshold + 1;
        TaskPlan reCrossPlan = ManagerTaskService.planHighValueTasks(
            new List<LoanRequestChange>{ LoanRequestChange.fromTrigger(raised, resetLoan) },
            settings
        );
        ManagerTaskService.commitTasks(reCrossPlan);

        System.assertEquals(1, reCrossPlan.size());
        System.assertEquals(
            2,
            [SELECT COUNT() FROM Task WHERE WhatId = :loan.Id]
        );
        System.assertEquals(
            true,
            [
                SELECT HighValueTaskCreated__c
                FROM LoanRequest__c
                WHERE Id = :loan.Id
            ]
            .HighValueTaskCreated__c
        );
    }

    @IsTest
    static void commitTasks_invalidTask_throwsMandatoryAutomationException() {
        isolateFromTrigger();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Draft',
            true
        );
        TaskPlan plan = new TaskPlan();
        // Invalid OwnerId (loan Id is not a User/Queue) forces Task DML failure.
        // Marker loan Id must be a real LoanRequest__c Id (not a User Id).
        plan.add(
            new Task(
                Subject = 'Invalid high-value task',
                WhatId = loan.Id,
                OwnerId = loan.Id
            ),
            loan.Id
        );

        Boolean threw = false;
        try {
            ManagerTaskService.commitTasks(plan);
        } catch (BankCrmException.MandatoryAutomationException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('Task'));
        }
        System.assertEquals(true, threw);
    }
}
