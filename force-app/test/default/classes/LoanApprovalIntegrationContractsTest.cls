/**
 * Unit coverage for outbound/callback JSON contracts and HTTP response mapping.
 */
@IsTest
private class LoanApprovalIntegrationContractsTest {
    @IsTest
    static void outboundRequest_fromLoanAndToJson() {
        Customer__c customer = BankCrmTestDataFactory.createCustomer(true);
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1500,
            'Submitted',
            true
        );
        loan.ExternalRequestId__c = BankCrmTestDataFactory.nextExternalRequestId();

        LoanApprovalIntegrationContracts.OutboundRequest request =
            LoanApprovalIntegrationContracts.outboundFromLoan(
                loan,
                customer.CustomerNumber__c,
                'corr-contracts-1'
            );
        String jsonBody = request.toJson();

        System.assertEquals(loan.ExternalRequestId__c, request.externalRequestId);
        System.assertEquals(customer.CustomerNumber__c, request.customerNumber);
        System.assertEquals(1500, request.loanAmount);
        System.assert(jsonBody.contains('externalRequestId'));
        System.assert(jsonBody.contains('corr-contracts-1'));
        System.assert(!jsonBody.toLowerCase().contains('national'));
    }

    @IsTest
    static void outboundResponse_fromHttp_successAndFailures() {
        HttpResponse success = new HttpResponse();
        success.setStatusCode(200);
        success.setStatus('OK');
        success.setBody(
            '{"externalRequestId":"EXT-1","externalDecisionReference":"DEC-9","message":"accepted"}'
        );
        LoanApprovalIntegrationContracts.OutboundResponse ok =
            LoanApprovalIntegrationContracts.outboundFromHttp(success);
        System.assertEquals(true, ok.success);
        System.assertEquals(false, ok.retryable);
        System.assertEquals('EXT-1', ok.externalRequestId);
        System.assertEquals('DEC-9', ok.externalDecisionReference);

        HttpResponse transientResp = new HttpResponse();
        transientResp.setStatusCode(503);
        transientResp.setStatus('Service Unavailable');
        transientResp.setBody('not-json');
        LoanApprovalIntegrationContracts.OutboundResponse retry =
            LoanApprovalIntegrationContracts.outboundFromHttp(transientResp);
        System.assertEquals(false, retry.success);
        System.assertEquals(true, retry.retryable);

        HttpResponse permanent = new HttpResponse();
        permanent.setStatusCode(401);
        permanent.setStatus('Unauthorized');
        permanent.setBody('{"message":"bad token","retryable":false}');
        LoanApprovalIntegrationContracts.OutboundResponse denied =
            LoanApprovalIntegrationContracts.outboundFromHttp(permanent);
        System.assertEquals(false, denied.success);
        System.assertEquals(false, denied.retryable);

        LoanApprovalIntegrationContracts.OutboundResponse nullResp =
            LoanApprovalIntegrationContracts.outboundFromHttp(null);
        System.assertEquals(false, nullResp.success);
        System.assertEquals(true, nullResp.retryable);
        System.assertEquals('NULL', nullResp.statusCode);
    }

    @IsTest
    static void approvalCallbackRequest_fromJson_andResults() {
        LoanApprovalIntegrationContracts.ApprovalCallbackRequest request =
            LoanApprovalIntegrationContracts.callbackFromJson(
                '{"externalRequestId":"EXT-2","decision":"Approved","correlationId":"c-1"}'
            );
        System.assertEquals('EXT-2', request.externalRequestId);
        System.assertEquals('Approved', request.decision);

        Boolean blankFailed = false;
        try {
            LoanApprovalIntegrationContracts.callbackFromJson(' ');
        } catch (BankCrmException.ValidationException ex) {
            blankFailed = true;
        }
        System.assertEquals(true, blankFailed);

        Id fakeLoanId = UserInfo.getUserId();
        LoanApprovalIntegrationContracts.ApprovalCallbackResult ok =
            LoanApprovalIntegrationContracts.callbackOk(fakeLoanId, 'done');
        System.assertEquals(true, ok.success);
        System.assertEquals(false, ok.duplicate);

        LoanApprovalIntegrationContracts.ApprovalCallbackResult dup =
            LoanApprovalIntegrationContracts.callbackDuplicate(fakeLoanId);
        System.assertEquals(true, dup.duplicate);

        LoanApprovalIntegrationContracts.ApprovalCallbackResult rejected =
            LoanApprovalIntegrationContracts.callbackRejected('nope');
        System.assertEquals(false, rejected.success);
        System.assertEquals('nope', rejected.message);
    }
}
