/**
 * Resolves Task/notification owners from customer relationship managers and settings fallbacks.
 * Prefer active RelationshipManager__c; otherwise CMDT username, then queue developer name.
 * Callers (e.g. ManagerTaskService) may log when fallback is used because the RM is inactive.
 */
public with sharing class UserRoutingResolver {
    /** Test seam: treat these user Ids as inactive even if the org user is active. */
    @TestVisible
    private static Set<Id> forcedInactiveUserIds;

    /**
     * Outcome for one customer routing resolution.
     */
    public class RoutingResult {
        public Id ownerId;
        public Boolean usedFallback;
        public Boolean relationshipManagerInactive;
        public String failureReason;

        public Boolean isSuccess() {
            return ownerId != null;
        }
    }

    public static Id resolveOwner(Customer__c customer, BankCrmSettings settings) {
        if (customer == null || customer.Id == null) {
            throw new BankCrmException.ValidationException(
                'Customer is required to resolve a manager owner.'
            );
        }
        Map<Id, Id> owners = resolveOwners(
            new Map<Id, Customer__c>{ customer.Id => customer },
            settings
        );
        return owners.get(customer.Id);
    }

    public static Map<Id, Id> resolveOwners(
        Map<Id, Customer__c> customers,
        BankCrmSettings settings
    ) {
        Map<Id, RoutingResult> detailed = resolveOwnersDetailed(customers, settings);
        Map<Id, Id> owners = new Map<Id, Id>();
        for (Id customerId : detailed.keySet()) {
            RoutingResult result = detailed.get(customerId);
            if (!result.isSuccess()) {
                throw new BankCrmException.ValidationException(
                    result.failureReason == null
                        ? 'Unable to resolve manager owner for customer ' + customerId
                        : result.failureReason
                );
            }
            owners.put(customerId, result.ownerId);
        }
        return owners;
    }

    public static Map<Id, RoutingResult> resolveOwnersDetailed(
        Map<Id, Customer__c> customers,
        BankCrmSettings settings
    ) {
        Map<Id, RoutingResult> results = new Map<Id, RoutingResult>();
        if (customers == null || customers.isEmpty()) {
            return results;
        }
        if (settings == null) {
            throw new BankCrmException('Bank CRM settings are required for owner routing.');
        }

        Set<Id> relationshipManagerIds = new Set<Id>();
        for (Customer__c customer : customers.values()) {
            if (customer != null && customer.RelationshipManager__c != null) {
                relationshipManagerIds.add(customer.RelationshipManager__c);
            }
        }

        Map<Id, User> activeManagersById = queryActiveUsersById(relationshipManagerIds);
        Id fallbackUserId = resolveFallbackUserId(settings.defaultManagerUsername);
        Id fallbackQueueId = resolveFallbackQueueId(settings.defaultQueueDeveloperName);

        for (Id customerId : customers.keySet()) {
            Customer__c customer = customers.get(customerId);
            RoutingResult result = new RoutingResult();
            result.usedFallback = false;
            result.relationshipManagerInactive = false;

            if (customer == null) {
                result.failureReason = 'Customer record is missing for Id ' + customerId;
                results.put(customerId, result);
                continue;
            }

            Id rmId = customer.RelationshipManager__c;
            if (rmId != null && activeManagersById.containsKey(rmId)) {
                result.ownerId = rmId;
                results.put(customerId, result);
                continue;
            }

            if (rmId != null && !activeManagersById.containsKey(rmId)) {
                result.relationshipManagerInactive = true;
            }

            if (String.isNotBlank(settings.defaultManagerUsername)) {
                if (fallbackUserId != null) {
                    result.ownerId = fallbackUserId;
                    result.usedFallback = true;
                    results.put(customerId, result);
                    continue;
                }
                result.failureReason =
                    'Configured default manager username was not found or is inactive: '
                    + settings.defaultManagerUsername;
                results.put(customerId, result);
                continue;
            }

            if (fallbackQueueId != null) {
                result.ownerId = fallbackQueueId;
                result.usedFallback = true;
                results.put(customerId, result);
                continue;
            }

            result.failureReason =
                'No active relationship manager and no configured default manager username or queue for customer '
                + customerId;
            results.put(customerId, result);
        }

        return results;
    }

    private static Map<Id, User> queryActiveUsersById(Set<Id> userIds) {
        Map<Id, User> activeById = new Map<Id, User>();
        if (userIds == null || userIds.isEmpty()) {
            return activeById;
        }
        for (User userRecord : [
            SELECT Id, IsActive
            FROM User
            WHERE Id IN :userIds AND IsActive = TRUE
        ]) {
            if (
                forcedInactiveUserIds != null &&
                forcedInactiveUserIds.contains(userRecord.Id)
            ) {
                continue;
            }
            activeById.put(userRecord.Id, userRecord);
        }
        return activeById;
    }

    private static Id resolveFallbackUserId(String username) {
        if (String.isBlank(username)) {
            return null;
        }
        List<User> users = [
            SELECT Id
            FROM User
            WHERE Username = :username AND IsActive = TRUE
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0].Id;
    }

    private static Id resolveFallbackQueueId(String queueDeveloperName) {
        if (String.isBlank(queueDeveloperName)) {
            return null;
        }
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :queueDeveloperName
            LIMIT 1
        ];
        return queues.isEmpty() ? null : queues[0].Id;
    }
}
