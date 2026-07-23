import { createElement } from 'lwc';
import LoanRequestSummary from 'c/loanRequestSummary';
import { subscribe, unsubscribe, MessageContext } from 'lightning/messageService';
import LOAN_REQUEST_CHANNEL from '@salesforce/messageChannel/Loan_Request_Message_Channel__c';
import getLoanRequest from '@salesforce/apex/LoanRequestReadController.getLoanRequest';

const LOAN_ID = 'a01XXXXXXXXXXXXXXX';
const CORRELATION_ID = 'corr-456';
const EMPTY_MESSAGE =
    'Save a loan on the left — this panel updates automatically from Salesforce.';

jest.mock(
    '@salesforce/apex/LoanRequestReadController.getLoanRequest',
    () => ({
        default: jest.fn()
    }),
    { virtual: true }
);

jest.mock(
    '@salesforce/messageChannel/Loan_Request_Message_Channel__c',
    () => ({
        default: 'Loan_Request_Message_Channel__c'
    }),
    { virtual: true }
);

jest.mock(
    '@salesforce/label/c.Bank_CRM_Summary_Empty',
    () => ({
        default: EMPTY_MESSAGE
    }),
    { virtual: true }
);

jest.mock(
    '@salesforce/label/c.Bank_CRM_Summary_Load_Error',
    () => ({ default: 'Unable to load the loan request summary. Try again.' }),
    { virtual: true }
);

jest.mock(
    '@salesforce/label/c.Bank_CRM_Summary_Loaded',
    () => ({ default: 'Loaded from Salesforce' }),
    { virtual: true }
);

jest.mock(
    '@salesforce/label/c.Bank_CRM_Summary_Next_Steps',
    () => ({
        default:
            'Open the record to change status to Approved or Rejected and verify customer status, email, and audit events.'
    }),
    { virtual: true }
);

function createComponent() {
    const element = createElement('c-loan-request-summary', {
        is: LoanRequestSummary
    });
    document.body.appendChild(element);
    return element;
}

async function flushPromises() {
    return Promise.resolve().then(() => Promise.resolve());
}

async function connectWithMessageContext() {
    subscribe.mockReturnValue({ id: 'loan-request-summary-subscription' });
    const element = createComponent();
    MessageContext.emit({});
    await flushPromises();
    return element;
}

function latestSubscribeHandler() {
    const calls = subscribe.mock.calls;
    expect(calls.length).toBeGreaterThan(0);
    return calls[calls.length - 1][2];
}

describe('c-loan-request-summary', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows empty state before any LMS message', async () => {
        const element = await connectWithMessageContext();

        expect(element.shadowRoot.textContent).toContain(EMPTY_MESSAGE);
        expect(getLoanRequest).not.toHaveBeenCalled();
    });

    it('subscribes on connect and unsubscribes on disconnect', async () => {
        const element = await connectWithMessageContext();

        expect(subscribe).toHaveBeenCalled();
        expect(subscribe.mock.calls[0][1]).toBe(LOAN_REQUEST_CHANNEL);

        document.body.removeChild(element);
        await flushPromises();
        expect(unsubscribe).toHaveBeenCalled();
    });

    it('reloads by Id from Salesforce after LMS message', async () => {
        getLoanRequest.mockResolvedValue({
            id: LOAN_ID,
            customerName: 'Acme Bank Customer',
            loanAmount: 250001,
            loanStatus: 'Submitted'
        });

        const element = await connectWithMessageContext();
        const handler = latestSubscribeHandler();

        handler({
            loanRequestId: LOAN_ID,
            correlationId: CORRELATION_ID,
            action: 'created',
            customerName: 'SHOULD_NOT_RENDER',
            loanAmount: 1,
            loanStatus: 'Draft'
        });
        await flushPromises();

        expect(getLoanRequest).toHaveBeenCalledWith({ loanRequestId: LOAN_ID });
        expect(element.shadowRoot.textContent).toContain('Acme Bank Customer');
        expect(element.shadowRoot.textContent).toContain('Submitted');
        expect(element.shadowRoot.textContent).toContain('Loaded from Salesforce');
        expect(element.shadowRoot.textContent).toContain('High value');
        expect(element.shadowRoot.textContent).toContain('What’s next');
        expect(element.shadowRoot.textContent).not.toContain('SHOULD_NOT_RENDER');
    });

    it('ignores malformed LMS Ids', async () => {
        const element = await connectWithMessageContext();
        const handler = latestSubscribeHandler();

        handler({
            loanRequestId: 'not-an-id',
            correlationId: CORRELATION_ID
        });
        await flushPromises();

        expect(getLoanRequest).not.toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain(EMPTY_MESSAGE);
    });

    it('shows error and Retry when reload fails', async () => {
        getLoanRequest.mockRejectedValue({
            body: { message: 'You do not have permission to perform this action.' }
        });

        const element = await connectWithMessageContext();
        const handler = latestSubscribeHandler();

        handler({
            loanRequestId: LOAN_ID,
            correlationId: CORRELATION_ID
        });
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'You do not have permission to perform this action.'
        );

        getLoanRequest.mockResolvedValue({
            id: LOAN_ID,
            customerName: 'Recovered Customer',
            loanAmount: 500,
            loanStatus: 'Draft'
        });

        element.shadowRoot
            .querySelector('lightning-button[title="Retry loading loan summary"]')
            .click();
        await flushPromises();

        expect(getLoanRequest).toHaveBeenCalledTimes(2);
        expect(element.shadowRoot.textContent).toContain('Recovered Customer');
    });
});
