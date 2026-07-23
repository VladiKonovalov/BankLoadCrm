/**
 * Authenticated REST boundary for external approval decisions.
 * Returns non-revealing error bodies; business work is delegated to ApprovalCallbackService.
 */
@RestResource(urlMapping='/bankcrm/v1/approval-callback')
global without sharing class ApprovalCallbackRestResource {
    private static final String AUTH_HEADER = 'X-Bank-CRM-Callback-Token';

    /** Org-configured shared secret; overridden in tests. Never commit real secrets. */
    @TestVisible
    private static String testAuthToken;

    @HttpPost
    global static void doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }
        res.addHeader('Content-Type', 'application/json');

        if (!isAuthorized(req)) {
            writeResponse(res, 401, '{"success":false,"message":"Unauthorized"}');
            return;
        }

        try {
            String body = req == null || req.requestBody == null
                ? null
                : req.requestBody.toString();
            LoanApprovalIntegrationContracts.ApprovalCallbackRequest callbackRequest =
                LoanApprovalIntegrationContracts.callbackFromJson(body);
            LoanApprovalIntegrationContracts.ApprovalCallbackResult result =
                ApprovalCallbackService.handleDecision(callbackRequest);

            if (result.success == true) {
                writeResponse(
                    res,
                    200,
                    JSON.serialize(
                        new Map<String, Object>{
                            'success' => true,
                            'duplicate' => result.duplicate == true,
                            'loanRequestId' => result.loanRequestId,
                            'message' => result.message
                        }
                    )
                );
            } else {
                writeResponse(
                    res,
                    400,
                    '{"success":false,"message":"Unable to process callback"}'
                );
            }
        } catch (BankCrmException.ValidationException vex) {
            writeResponse(
                res,
                400,
                '{"success":false,"message":"Unable to process callback"}'
            );
        } catch (Exception ex) {
            ApplicationErrorService.ErrorContext errorCtx =
                new ApplicationErrorService.ErrorContext(
                    'ApprovalCallbackRestResource',
                    'doPost'
                );
            errorCtx.category = 'Integration Permanent';
            errorCtx.retryable = false;
            ApplicationErrorService.log(ex, errorCtx);
            writeResponse(
                res,
                500,
                '{"success":false,"message":"Unable to process callback"}'
            );
        }
    }

    private static Boolean isAuthorized(RestRequest req) {
        if (req == null) {
            return false;
        }
        String provided = req.headers == null ? null : req.headers.get(AUTH_HEADER);
        if (String.isBlank(provided)) {
            // Header names can vary by case depending on client.
            if (req.headers != null) {
                for (String key : req.headers.keySet()) {
                    if (key != null && key.toLowerCase() == AUTH_HEADER.toLowerCase()) {
                        provided = req.headers.get(key);
                        break;
                    }
                }
            }
        }
        String expected = resolveExpectedToken();
        return String.isNotBlank(expected)
            && String.isNotBlank(provided)
            && provided == expected;
    }

    private static String resolveExpectedToken() {
        if (Test.isRunningTest() && String.isNotBlank(testAuthToken)) {
            return testAuthToken;
        }
        try {
            String labelValue = System.Label.Bank_CRM_Callback_Token;
            if (String.isNotBlank(labelValue) && labelValue != 'REPLACE_IN_ORG') {
                return labelValue;
            }
        } catch (Exception ignore) {
            // Label may be absent in early deploys; fall through.
        }
        if (Test.isRunningTest()) {
            return 'test-callback-token';
        }
        return null;
    }

    private static void writeResponse(RestResponse res, Integer statusCode, String body) {
        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(body);
    }
}
