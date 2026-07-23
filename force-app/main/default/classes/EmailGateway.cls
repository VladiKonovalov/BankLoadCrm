/**
 * Thin Messaging API boundary so approval email success/failure is testable.
 */
public with sharing class EmailGateway {
    @TestVisible
    private static Boolean mockThrow = false;
    @TestVisible
    private static final List<Messaging.SingleEmailMessage> capturedMessages =
        new List<Messaging.SingleEmailMessage>();

    public static void resetTestState() {
        mockThrow = false;
        capturedMessages.clear();
    }

    public static List<Messaging.SingleEmailMessage> getCapturedMessages() {
        return new List<Messaging.SingleEmailMessage>(capturedMessages);
    }

    /**
     * Sends emails and returns platform results.
     * When mockThrow is true in tests, throws before Messaging is invoked.
     */
    public static List<Messaging.SendEmailResult> send(
        List<Messaging.SingleEmailMessage> messages,
        Boolean allOrNone
    ) {
        if (messages == null || messages.isEmpty()) {
            return new List<Messaging.SendEmailResult>();
        }
        capturedMessages.addAll(messages);

        if (Test.isRunningTest() && mockThrow == true) {
            throw new BankCrmException('Mock email send failure');
        }

        return Messaging.sendEmail(messages, allOrNone == true);
    }
}
