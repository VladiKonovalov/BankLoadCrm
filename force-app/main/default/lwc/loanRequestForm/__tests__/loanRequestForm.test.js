import { createElement } from 'lwc';
import LoanRequestForm from 'c/loanRequestForm';
import { publish } from 'lightning/messageService';
import LOAN_REQUEST_CHANNEL from '@salesforce/messageChannel/Loan_Request_Message_Channel__c';
import saveLoanRequest from '@salesforce/apex/LoanRequestController.saveLoanRequest';

const LOAN_ID = 'a01XXXXXXXXXXXXXXX';
const CORRELATION_ID = 'corr-123';

jest.mock(
    '@salesforce/apex/LoanRequestController.saveLoanRequest',
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
    '@salesforce/label/c.Bank_CRM_Save_Success',
    () => ({ default: 'Loan request saved — summary updated from Salesforce.' }),
    { virtual: true }
);

jest.mock(
    '@salesforce/label/c.Bank_CRM_Generic_Save_Error',
    () => ({
        default: 'Unable to save the loan request. Review the entered values and try again.'
    }),
    { virtual: true }
);

jest.mock(
    '@salesforce/label/c.Bank_CRM_High_Value_Hint',
    () => ({
        default:
            'Amounts over ₪250,000 notify the manager and create Task/audit records.'
    }),
    { virtual: true }
);

function createComponent() {
    const element = createElement('c-loan-request-form', {
        is: LoanRequestForm
    });
    document.body.appendChild(element);
    return element;
}

async function flushPromises() {
    return Promise.resolve().then(() => Promise.resolve());
}

function clickSave(element) {
    element.shadowRoot
        .querySelector('lightning-button[title="Save loan request"]')
        .click();
}

function fillValidForm(element) {
    const picker = element.shadowRoot.querySelector('lightning-record-picker');
    picker.dispatchEvent(
        new CustomEvent('change', {
            detail: { recordId: 'a00XXXXXXXXXXXXXXX' }
        })
    );

    const amountInput = element.shadowRoot.querySelector('lightning-input');
    amountInput.dispatchEvent(
        new CustomEvent('change', {
            detail: { value: '1000' }
        })
    );

    const status = element.shadowRoot.querySelector('lightning-combobox');
    status.dispatchEvent(
        new CustomEvent('change', {
            detail: { value: 'Draft' }
        })
    );
}

describe('c-loan-request-form', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('blocks Apex and LMS when client validation fails', async () => {
        const element = createComponent();
        await flushPromises();

        clickSave(element);
        await flushPromises();

        expect(saveLoanRequest).not.toHaveBeenCalled();
        expect(publish).not.toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain('Customer is required.');
    });

    it('blocks Apex and LMS for non-positive amount', async () => {
        const element = createComponent();
        await flushPromises();

        const picker = element.shadowRoot.querySelector('lightning-record-picker');
        picker.dispatchEvent(
            new CustomEvent('change', {
                detail: { recordId: 'a00XXXXXXXXXXXXXXX' }
            })
        );
        const amountInput = element.shadowRoot.querySelector('lightning-input');
        amountInput.dispatchEvent(
            new CustomEvent('change', {
                detail: { value: '0' }
            })
        );

        clickSave(element);
        await flushPromises();

        expect(saveLoanRequest).not.toHaveBeenCalled();
        expect(publish).not.toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain(
            'Loan amount must be greater than zero.'
        );
    });

    it('shows high-value hint when amount exceeds threshold', async () => {
        const element = createComponent();
        await flushPromises();

        const overThreshold = element.shadowRoot.querySelector(
            'lightning-button[data-amount="250001"]'
        );
        overThreshold.click();
        await flushPromises();

        expect(element.shadowRoot.textContent).toContain(
            'Amounts over ₪250,000 notify the manager and create Task/audit records.'
        );
    });

    it('publishes Id-only LMS payload after successful save', async () => {
        saveLoanRequest.mockResolvedValue({
            success: true,
            loanRequestId: LOAN_ID,
            correlationId: CORRELATION_ID,
            errors: []
        });

        const element = createComponent();
        await flushPromises();
        fillValidForm(element);

        clickSave(element);
        await flushPromises();

        expect(saveLoanRequest).toHaveBeenCalledTimes(1);
        expect(saveLoanRequest).toHaveBeenCalledWith({
            dto: {
                customerId: 'a00XXXXXXXXXXXXXXX',
                loanAmount: 1000,
                loanStatus: 'Draft'
            }
        });
        expect(publish).toHaveBeenCalledTimes(1);
        const publishArgs = publish.mock.calls[0];
        expect(publishArgs[1]).toBe(LOAN_REQUEST_CHANNEL);
        expect(publishArgs[2]).toEqual({
            loanRequestId: LOAN_ID,
            correlationId: CORRELATION_ID,
            action: 'created'
        });
        expect(publishArgs[2].customerName).toBeUndefined();
        expect(publishArgs[2].loanAmount).toBeUndefined();
        expect(publishArgs[2].loanStatus).toBeUndefined();
        expect(element.shadowRoot.textContent).toContain(
            'Saved. Summary updated from Salesforce.'
        );
        expect(
            element.shadowRoot.querySelector(
                'button[title="Open the saved loan request record"]'
            )
        ).not.toBeNull();
    });

    it('does not publish LMS when Apex returns validation failures', async () => {
        saveLoanRequest.mockResolvedValue({
            success: false,
            correlationId: CORRELATION_ID,
            errors: [{ fieldApiName: 'loanAmount', message: 'Loan amount is required.' }]
        });

        const element = createComponent();
        await flushPromises();
        fillValidForm(element);

        clickSave(element);
        await flushPromises();

        expect(saveLoanRequest).toHaveBeenCalledTimes(1);
        expect(publish).not.toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain('Loan amount is required.');
    });

    it('does not publish LMS when Apex rejects', async () => {
        saveLoanRequest.mockRejectedValue({
            body: { message: 'You do not have permission to perform this action.' }
        });

        const element = createComponent();
        await flushPromises();
        fillValidForm(element);

        clickSave(element);
        await flushPromises();

        expect(publish).not.toHaveBeenCalled();
        expect(element.shadowRoot.textContent).toContain(
            'You do not have permission to perform this action.'
        );
    });

    it('prevents duplicate Apex calls while saving', async () => {
        let resolveSave;
        saveLoanRequest.mockImplementation(
            () =>
                new Promise((resolve) => {
                    resolveSave = resolve;
                })
        );

        const element = createComponent();
        await flushPromises();
        fillValidForm(element);

        const button = element.shadowRoot.querySelector(
            'lightning-button[title="Save loan request"]'
        );
        button.click();
        button.click();
        await flushPromises();

        expect(saveLoanRequest).toHaveBeenCalledTimes(1);

        resolveSave({
            success: true,
            loanRequestId: LOAN_ID,
            correlationId: CORRELATION_ID,
            errors: []
        });
        await flushPromises();
    });
});
