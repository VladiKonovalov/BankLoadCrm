/**
 * Builds approval Messaging.SingleEmailMessage instances from Custom Labels.
 */
public with sharing class EmailMessageBuilder {
    public class CustomerEmailContext {
        public String customerName;
        public String recipientEmail;
        public String loanReference;
        public Decimal loanAmount;
        public String correlationId;

        public CustomerEmailContext(
            String customerName,
            String recipientEmail,
            String loanReference,
            Decimal loanAmount,
            String correlationId
        ) {
            this.customerName = customerName;
            this.recipientEmail = recipientEmail;
            this.loanReference = loanReference;
            this.loanAmount = loanAmount;
            this.correlationId = correlationId;
        }
    }

    public static Messaging.SingleEmailMessage buildApprovalEmail(CustomerEmailContext ctx) {
        if (ctx == null) {
            throw new BankCrmException.ValidationException('Customer email context is required.');
        }
        if (String.isBlank(ctx.recipientEmail)) {
            throw new BankCrmException.ValidationException('Recipient email is required.');
        }

        String loanRef = String.isBlank(ctx.loanReference) ? '' : ctx.loanReference;
        String customerName = String.isBlank(ctx.customerName) ? 'Customer' : ctx.customerName;
        String amountText = ctx.loanAmount == null ? '' : String.valueOf(ctx.loanAmount);

        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setToAddresses(new List<String>{ ctx.recipientEmail });
        message.setSubject(
            String.format(
                System.Label.Bank_CRM_Approval_Email_Subject,
                new List<String>{ loanRef }
            )
        );
        message.setPlainTextBody(
            String.format(
                System.Label.Bank_CRM_Approval_Email_Body,
                new List<String>{ customerName, loanRef, amountText }
            )
        );
        message.setSaveAsActivity(false);
        return message;
    }
}
