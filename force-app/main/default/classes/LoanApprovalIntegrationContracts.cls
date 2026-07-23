/**
 * Vendor payload contracts for outbound approval, responses, and callbacks.
 * Factory helpers live on the outer type because Apex forbids static methods on inner classes.
 */
public with sharing class LoanApprovalIntegrationContracts {
    public class OutboundRequest {
        public String externalRequestId;
        public String customerNumber;
        public Decimal loanAmount;
        public String loanStatus;
        public String correlationId;
        public String currencyCode;
        public String loanRequestId;

        public String toJson() {
            Map<String, Object> body = new Map<String, Object>{
                'externalRequestId' => externalRequestId,
                'customerNumber' => customerNumber,
                'loanAmount' => loanAmount,
                'loanStatus' => loanStatus,
                'correlationId' => correlationId,
                'currencyCode' => currencyCode,
                'loanRequestId' => loanRequestId
            };
            return JSON.serialize(body);
        }
    }

    public class OutboundResponse {
        public Boolean success;
        public String externalRequestId;
        public String externalDecisionReference;
        public String statusCode;
        public String message;
        public Boolean retryable;
    }

    public class ApprovalCallbackRequest {
        public String externalRequestId;
        public String externalDecisionReference;
        public String decision;
        public String decisionReason;
        public String correlationId;
    }

    public class ApprovalCallbackResult {
        public Boolean success;
        public Boolean duplicate;
        public String message;
        public Id loanRequestId;
    }

    public static OutboundRequest outboundFromLoan(
        LoanRequest__c loan,
        String customerNumber,
        String correlationId
    ) {
        OutboundRequest request = new OutboundRequest();
        request.externalRequestId = loan.ExternalRequestId__c;
        request.customerNumber = customerNumber;
        request.loanAmount = loan.LoanAmount__c;
        request.loanStatus = loan.LoanStatus__c;
        request.correlationId = correlationId;
        request.currencyCode = UserInfo.getDefaultCurrency();
        request.loanRequestId = loan.Id == null ? null : String.valueOf(loan.Id);
        return request;
    }

    public static OutboundResponse outboundFromHttp(HttpResponse httpResponse) {
        OutboundResponse response = new OutboundResponse();
        if (httpResponse == null) {
            response.success = false;
            response.retryable = true;
            response.statusCode = 'NULL';
            response.message = 'No HTTP response received.';
            return response;
        }

        Integer code = httpResponse.getStatusCode();
        response.statusCode = String.valueOf(code);
        response.message = SanitizedMessageUtil.sanitize(httpResponse.getStatus());

        if (code >= 200 && code < 300) {
            response.success = true;
            response.retryable = false;
            populateFromBody(response, httpResponse.getBody());
            return response;
        }

        response.success = false;
        response.retryable = isTransientStatus(code);
        populateFromBody(response, httpResponse.getBody());
        if (String.isBlank(response.message)) {
            response.message = SanitizedMessageUtil.sanitize(
                'HTTP ' + code + ' from approval API'
            );
        }
        return response;
    }

    public static ApprovalCallbackRequest callbackFromJson(String jsonBody) {
        if (String.isBlank(jsonBody)) {
            throw new BankCrmException.ValidationException('Callback body is required.');
        }
        ApprovalCallbackRequest request = (ApprovalCallbackRequest) JSON.deserialize(
            jsonBody,
            ApprovalCallbackRequest.class
        );
        if (request == null) {
            throw new BankCrmException.ValidationException('Callback body is invalid.');
        }
        return request;
    }

    public static ApprovalCallbackResult callbackOk(Id loanId, String message) {
        ApprovalCallbackResult result = new ApprovalCallbackResult();
        result.success = true;
        result.duplicate = false;
        result.loanRequestId = loanId;
        result.message = message;
        return result;
    }

    public static ApprovalCallbackResult callbackDuplicate(Id loanId) {
        ApprovalCallbackResult result = new ApprovalCallbackResult();
        result.success = true;
        result.duplicate = true;
        result.loanRequestId = loanId;
        result.message = 'Duplicate callback ignored.';
        return result;
    }

    public static ApprovalCallbackResult callbackRejected(String message) {
        ApprovalCallbackResult result = new ApprovalCallbackResult();
        result.success = false;
        result.duplicate = false;
        result.message = message;
        return result;
    }

    private static void populateFromBody(OutboundResponse response, String body) {
        if (String.isBlank(body)) {
            return;
        }
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
            if (parsed.containsKey('externalRequestId')) {
                response.externalRequestId = String.valueOf(parsed.get('externalRequestId'));
            }
            if (parsed.containsKey('externalDecisionReference')) {
                response.externalDecisionReference = String.valueOf(
                    parsed.get('externalDecisionReference')
                );
            }
            if (parsed.containsKey('message')) {
                response.message = SanitizedMessageUtil.sanitize(
                    String.valueOf(parsed.get('message'))
                );
            }
            if (parsed.containsKey('retryable') && parsed.get('retryable') != null) {
                response.retryable = (Boolean) parsed.get('retryable');
            }
        } catch (Exception ignore) {
            // Non-JSON bodies are acceptable; status code drives retryability.
        }
    }

    private static Boolean isTransientStatus(Integer code) {
        return code == 408
            || code == 429
            || (code >= 500 && code <= 599);
    }
}
