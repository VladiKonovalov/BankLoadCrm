/**
 * Flow bridge: resolves a User Id for custom manager notifications.
 * Reuses UserRoutingResolver (RM → username → queue) but rejects Queue Ids
 * because custom notifications require User recipients.
 */
public with sharing class ManagerNotificationRecipientInvocable {
    public class Request {
        @InvocableVariable(required=true label='Customer Id')
        public Id customerId;
    }

    public class Result {
        @InvocableVariable(label='Recipient User Id')
        public Id recipientUserId;

        @InvocableVariable(label='Is Resolved')
        public Boolean isResolved;

        @InvocableVariable(label='Failure Reason')
        public String failureReason;
    }

    @InvocableMethod(
        label='Resolve Manager Notification Recipient'
        description='Resolves an active User Id for high-value loan custom notifications. Queue-only routing is treated as unresolved.'
        category='Bank CRM'
    )
    public static List<Result> resolve(List<Request> requests) {
        List<Result> results = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<Id> customerIds = new Set<Id>();
        for (Request request : requests) {
            if (request != null && request.customerId != null) {
                customerIds.add(request.customerId);
            }
        }

        Map<Id, Customer__c> customersById = customerIds.isEmpty()
            ? new Map<Id, Customer__c>()
            : new Map<Id, Customer__c>([
                SELECT Id, RelationshipManager__c
                FROM Customer__c
                WHERE Id IN :customerIds
            ]);

        BankCrmSettings settings;
        try {
            settings = BankCrmSettingsProvider.getSettings();
        } catch (Exception ex) {
            for (Request request : requests) {
                results.add(
                    unresolved(
                        'Bank CRM settings are unavailable for notification recipient routing.'
                    )
                );
            }
            return results;
        }

        Map<Id, UserRoutingResolver.RoutingResult> routingByCustomerId =
            UserRoutingResolver.resolveOwnersDetailed(customersById, settings);

        for (Request request : requests) {
            if (request == null || request.customerId == null) {
                results.add(unresolved('Customer Id is required to resolve a notification recipient.'));
                continue;
            }

            Customer__c customer = customersById.get(request.customerId);
            if (customer == null) {
                results.add(unresolved('Customer record was not found for notification recipient routing.'));
                continue;
            }

            UserRoutingResolver.RoutingResult route = routingByCustomerId.get(request.customerId);
            if (route == null || !route.isSuccess()) {
                results.add(
                    unresolved(
                        route != null && String.isNotBlank(route.failureReason)
                            ? route.failureReason
                            : 'Manager recipient unresolved; skipping custom notification and continuing to high-value audit.'
                    )
                );
                continue;
            }

            if (route.ownerId.getSObjectType() != User.SObjectType) {
                results.add(
                    unresolved(
                        'Resolved owner is not a User; custom notifications require a User Id. Skipping notification and continuing to high-value audit.'
                    )
                );
                continue;
            }

            Result success = new Result();
            success.recipientUserId = route.ownerId;
            success.isResolved = true;
            success.failureReason = null;
            results.add(success);
        }

        return results;
    }

    private static Result unresolved(String reason) {
        Result result = new Result();
        result.recipientUserId = null;
        result.isResolved = false;
        result.failureReason = reason;
        return result;
    }
}
