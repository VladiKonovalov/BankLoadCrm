/**
 * Shared HttpCalloutMock for Bank CRM approval integration tests.
 */
@IsTest
public class BankCrmHttpCalloutMock implements HttpCalloutMock {
    public enum Mode {
        SUCCESS,
        TRANSIENT_5XX,
        PERMANENT_401,
        TIMEOUT_LIKE
    }

    private final Mode responseMode;
    private final String decisionReference;

    public BankCrmHttpCalloutMock(Mode responseMode) {
        this(responseMode, 'EXT-DEC-001');
    }

    public BankCrmHttpCalloutMock(Mode responseMode, String decisionReference) {
        this.responseMode = responseMode;
        this.decisionReference = decisionReference;
    }

    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        if (responseMode == BankCrmHttpCalloutMock.Mode.SUCCESS) {
            res.setStatusCode(202);
            res.setStatus('Accepted');
            res.setBody(
                '{"externalDecisionReference":"' +
                decisionReference +
                '","message":"accepted"}'
            );
        } else if (responseMode == BankCrmHttpCalloutMock.Mode.TRANSIENT_5XX) {
            res.setStatusCode(503);
            res.setStatus('Service Unavailable');
            res.setBody('{"message":"temporary","retryable":true}');
        } else if (responseMode == BankCrmHttpCalloutMock.Mode.PERMANENT_401) {
            res.setStatusCode(401);
            res.setStatus('Unauthorized');
            res.setBody('{"message":"invalid credentials","retryable":false}');
        } else {
            // Simulate transport failure via non-success without retryable flag; orchestrator
            // treats 5xx-like codes as transient. Use 408 Request Timeout.
            res.setStatusCode(408);
            res.setStatus('Request Timeout');
            res.setBody('{"message":"timeout"}');
        }
        return res;
    }
}
