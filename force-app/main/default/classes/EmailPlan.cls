/**
 * Collects prepared approval email side effects before one bulk send.
 */
public with sharing class EmailPlan {
    public class EmailItem {
        public Id loanRequestId;
        public Id customerId;
        public String recipientEmail;
        public String customerName;
        public String loanReference;
        public Decimal loanAmount;
        public String correlationId;

        public EmailItem(
            Id loanRequestId,
            Id customerId,
            String recipientEmail,
            String customerName,
            String loanReference,
            Decimal loanAmount,
            String correlationId
        ) {
            this.loanRequestId = loanRequestId;
            this.customerId = customerId;
            this.recipientEmail = recipientEmail;
            this.customerName = customerName;
            this.loanReference = loanReference;
            this.loanAmount = loanAmount;
            this.correlationId = correlationId;
        }
    }

    private final List<EmailItem> items = new List<EmailItem>();

    public void add(EmailItem item) {
        if (item == null) {
            return;
        }
        items.add(item);
    }

    public Boolean isEmpty() {
        return items.isEmpty();
    }

    public List<EmailItem> getItems() {
        return new List<EmailItem>(items);
    }

    public Integer size() {
        return items.size();
    }
}
