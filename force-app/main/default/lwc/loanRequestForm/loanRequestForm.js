import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { MessageContext, publish } from 'lightning/messageService';
import LOAN_REQUEST_CHANNEL from '@salesforce/messageChannel/Loan_Request_Message_Channel__c';
import saveLoanRequest from '@salesforce/apex/LoanRequestController.saveLoanRequest';
import LABEL_SAVE_SUCCESS from '@salesforce/label/c.Bank_CRM_Save_Success';
import LABEL_GENERIC_SAVE_ERROR from '@salesforce/label/c.Bank_CRM_Generic_Save_Error';
import LABEL_HIGH_VALUE_HINT from '@salesforce/label/c.Bank_CRM_High_Value_Hint';

const CREATE_STATUS_OPTIONS = [
    { label: 'Draft', value: 'Draft' },
    { label: 'Submitted', value: 'Submitted' }
];

const ALLOWED_CREATE_STATUSES = new Set(['Draft', 'Submitted']);

/** Assignment threshold: escalate when amount is strictly greater than this value. */
const HIGH_VALUE_THRESHOLD = 250000;

const AMOUNT_PRESETS = [
    {
        label: '₪100,000',
        value: 100000,
        title: 'Under high-value threshold'
    },
    {
        label: '₪250,001',
        value: 250001,
        title: 'Over high-value threshold — manager Task / audit'
    }
];

export default class LoanRequestForm extends NavigationMixin(LightningElement) {
    customerId;
    loanAmount;
    loanStatus = 'Draft';
    isSaving = false;
    formError;
    customerError;
    amountError;
    statusError;
    lastSavedId;

    customerDisplayInfo = {
        primaryField: 'Name',
        additionalFields: ['CustomerNumber__c']
    };

    customerMatchingInfo = {
        primaryField: { fieldPath: 'Name' },
        additionalFields: [{ fieldPath: 'CustomerNumber__c' }]
    };

    @wire(MessageContext)
    messageContext;

    get statusOptions() {
        return CREATE_STATUS_OPTIONS;
    }

    get amountPresets() {
        return AMOUNT_PRESETS;
    }

    get highValueHint() {
        return LABEL_HIGH_VALUE_HINT;
    }

    get showHighValueHint() {
        return Number(this.loanAmount) > HIGH_VALUE_THRESHOLD;
    }

    get isSaveDisabled() {
        return this.isSaving;
    }

    handleCustomerChange(event) {
        this.customerId = event.detail.recordId;
        this.customerError = undefined;
        this.formError = undefined;
    }

    handleAmountChange(event) {
        const raw =
            event.detail && event.detail.value !== undefined
                ? event.detail.value
                : event.target.value;
        this.loanAmount = raw === '' || raw === null || raw === undefined ? null : Number(raw);
        this.amountError = undefined;
        this.formError = undefined;
    }

    handleAmountPreset(event) {
        const amount = Number(event.currentTarget.dataset.amount);
        if (!Number.isFinite(amount)) {
            return;
        }
        this.loanAmount = amount;
        this.amountError = undefined;
        this.formError = undefined;
    }

    handleStatusChange(event) {
        this.loanStatus = event.detail.value;
        this.statusError = undefined;
        this.formError = undefined;
    }

    handleClear() {
        if (this.isSaving) {
            return;
        }
        this.customerId = undefined;
        this.loanAmount = null;
        this.loanStatus = 'Draft';
        this.lastSavedId = undefined;
        this.clearErrors();
    }

    handleOpenSavedRecord() {
        if (!this.lastSavedId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.lastSavedId,
                objectApiName: 'LoanRequest__c',
                actionName: 'view'
            }
        });
    }

    async handleSave() {
        if (this.isSaving) {
            return;
        }

        this.clearErrors();
        if (!this.validateClient()) {
            return;
        }

        this.isSaving = true;
        try {
            const result = await saveLoanRequest({
                dto: {
                    customerId: this.customerId,
                    loanAmount: this.loanAmount,
                    loanStatus: this.loanStatus
                }
            });

            if (!result || result.success !== true) {
                this.applyServerFailures(result);
                return;
            }

            this.lastSavedId = result.loanRequestId;
            this.publishSuccess(result);
            this.showSuccessToast();
            this.resetAfterSuccess();
        } catch (error) {
            this.formError = this.resolveApexErrorMessage(error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save failed',
                    message: this.formError,
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }

    validateClient() {
        let valid = true;

        if (!this.customerId) {
            this.customerError = 'Customer is required.';
            valid = false;
        }

        if (this.loanAmount === null || this.loanAmount === undefined || this.loanAmount === '') {
            this.amountError = 'Loan amount is required.';
            valid = false;
        } else if (!(Number(this.loanAmount) > 0)) {
            this.amountError = 'Loan amount must be greater than zero.';
            valid = false;
        }

        if (!this.loanStatus) {
            this.statusError = 'Loan status is required.';
            valid = false;
        } else if (!ALLOWED_CREATE_STATUSES.has(this.loanStatus)) {
            this.statusError = 'New loan requests may only start as Draft or Submitted.';
            valid = false;
        }

        return valid;
    }

    applyServerFailures(result) {
        const failures = result && Array.isArray(result.errors) ? result.errors : [];
        if (failures.length === 0) {
            this.formError = LABEL_GENERIC_SAVE_ERROR;
            return;
        }

        let mappedField = false;
        for (const failure of failures) {
            const field = failure.fieldApiName;
            const message = failure.message || LABEL_GENERIC_SAVE_ERROR;
            if (field === 'customerId' || field === 'Customer__c') {
                this.customerError = message;
                mappedField = true;
            } else if (field === 'loanAmount' || field === 'LoanAmount__c') {
                this.amountError = message;
                mappedField = true;
            } else if (field === 'loanStatus' || field === 'LoanStatus__c') {
                this.statusError = message;
                mappedField = true;
            } else {
                this.formError = message;
                mappedField = true;
            }
        }

        if (!mappedField) {
            this.formError = LABEL_GENERIC_SAVE_ERROR;
        }
    }

    publishSuccess(result) {
        publish(this.messageContext, LOAN_REQUEST_CHANNEL, {
            loanRequestId: result.loanRequestId,
            correlationId: result.correlationId,
            action: 'created'
        });
    }

    showSuccessToast() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: LABEL_SAVE_SUCCESS,
                variant: 'success'
            })
        );
    }

    resetAfterSuccess() {
        // Keep customer for rapid repeat entry; reset amount/status defaults.
        this.loanAmount = null;
        this.loanStatus = 'Draft';
        this.clearErrors();
    }

    clearErrors() {
        this.formError = undefined;
        this.customerError = undefined;
        this.amountError = undefined;
        this.statusError = undefined;
    }

    resolveApexErrorMessage(error) {
        const bodyMessage =
            error &&
            error.body &&
            (error.body.message ||
                (Array.isArray(error.body.pageErrors) &&
                    error.body.pageErrors[0] &&
                    error.body.pageErrors[0].message));
        if (bodyMessage) {
            return bodyMessage;
        }
        if (error && typeof error.message === 'string' && error.message) {
            return error.message;
        }
        return LABEL_GENERIC_SAVE_ERROR;
    }
}
