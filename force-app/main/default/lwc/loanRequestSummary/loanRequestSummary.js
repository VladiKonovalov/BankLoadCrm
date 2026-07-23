import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import {
    APPLICATION_SCOPE,
    MessageContext,
    subscribe,
    unsubscribe
} from 'lightning/messageService';
import LOAN_REQUEST_CHANNEL from '@salesforce/messageChannel/Loan_Request_Message_Channel__c';
import getLoanRequest from '@salesforce/apex/LoanRequestReadController.getLoanRequest';
import LABEL_SUMMARY_EMPTY from '@salesforce/label/c.Bank_CRM_Summary_Empty';
import LABEL_SUMMARY_LOAD_ERROR from '@salesforce/label/c.Bank_CRM_Summary_Load_Error';
import LABEL_SUMMARY_LOADED from '@salesforce/label/c.Bank_CRM_Summary_Loaded';
import LABEL_SUMMARY_NEXT_STEPS from '@salesforce/label/c.Bank_CRM_Summary_Next_Steps';

const SALESFORCE_ID_PATTERN = /^[a-zA-Z0-9]{15}$|^[a-zA-Z0-9]{18}$/;
const HIGH_VALUE_THRESHOLD = 250000;

export default class LoanRequestSummary extends NavigationMixin(LightningElement) {
    loanRequestId;
    correlationId;
    customerName;
    loanAmount;
    loanStatus;
    isLoading = false;
    loadError;
    hasLoadedData = false;
    subscription;
    messageContext;

    @wire(MessageContext)
    wiredMessageContext(context) {
        this.messageContext = context;
        this.subscribeToChannel();
    }

    disconnectedCallback() {
        this.unsubscribeFromChannel();
    }

    get emptyMessage() {
        return LABEL_SUMMARY_EMPTY;
    }

    get loadedFromSalesforceLabel() {
        return LABEL_SUMMARY_LOADED;
    }

    get nextStepsLabel() {
        return LABEL_SUMMARY_NEXT_STEPS;
    }

    get showEmpty() {
        return !this.isLoading && !this.loadError && !this.hasLoadedData;
    }

    get showError() {
        return Boolean(this.loadError);
    }

    get showData() {
        return this.hasLoadedData;
    }

    get isHighValue() {
        return Number(this.loanAmount) > HIGH_VALUE_THRESHOLD;
    }

    get statusBadgeClass() {
        const status = (this.loanStatus || '').toLowerCase().replace(/\s+/g, '-');
        const base = 'status-badge';
        if (status === 'approved') {
            return `${base} status-badge_approved`;
        }
        if (status === 'rejected') {
            return `${base} status-badge_rejected`;
        }
        if (status === 'submitted' || status === 'under-review') {
            return `${base} status-badge_progress`;
        }
        if (status === 'integration-error') {
            return `${base} status-badge_error`;
        }
        return `${base} status-badge_neutral`;
    }

    subscribeToChannel() {
        if (this.subscription || !this.messageContext) {
            return;
        }
        this.subscription = subscribe(
            this.messageContext,
            LOAN_REQUEST_CHANNEL,
            (message) => this.handleMessage(message),
            { scope: APPLICATION_SCOPE }
        );
    }

    unsubscribeFromChannel() {
        if (this.subscription) {
            unsubscribe(this.subscription);
            this.subscription = undefined;
        }
    }

    handleMessage(message) {
        if (!message || !this.isValidId(message.loanRequestId)) {
            return;
        }
        this.loanRequestId = message.loanRequestId;
        this.correlationId = message.correlationId;
        this.loadLoan(this.loanRequestId);
    }

    handleRetry() {
        if (!this.loanRequestId || this.isLoading) {
            return;
        }
        this.loadLoan(this.loanRequestId);
    }

    handleOpenRecord() {
        if (!this.loanRequestId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.loanRequestId,
                objectApiName: 'LoanRequest__c',
                actionName: 'view'
            }
        });
    }

    async loadLoan(loanRequestId) {
        this.isLoading = true;
        this.loadError = undefined;
        try {
            const dto = await getLoanRequest({ loanRequestId });
            if (!dto) {
                this.loadError = LABEL_SUMMARY_LOAD_ERROR;
                return;
            }
            this.customerName = dto.customerName;
            this.loanAmount = dto.loanAmount;
            this.loanStatus = dto.loanStatus;
            this.hasLoadedData = true;
        } catch (error) {
            this.loadError = this.resolveLoadError(error);
        } finally {
            this.isLoading = false;
        }
    }

    isValidId(value) {
        return typeof value === 'string' && SALESFORCE_ID_PATTERN.test(value);
    }

    resolveLoadError(error) {
        const bodyMessage = error && error.body && error.body.message;
        if (bodyMessage) {
            return bodyMessage;
        }
        return LABEL_SUMMARY_LOAD_ERROR;
    }
}
