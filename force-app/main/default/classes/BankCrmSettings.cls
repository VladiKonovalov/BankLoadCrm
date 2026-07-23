/**
 * Immutable runtime representation of Bank_CRM_Settings__mdt policy.
 */
public with sharing class BankCrmSettings {
    public final Decimal highValueThreshold;
    public final String defaultManagerUsername;
    public final String defaultQueueDeveloperName;
    public final String managerNotificationType;
    public final Integer retryLimit;
    public final Boolean integrationEnabled;
    public final Integer retryBaseDelayMinutes;
    public final String developerName;

    public BankCrmSettings(
        Decimal highValueThreshold,
        String defaultManagerUsername,
        String defaultQueueDeveloperName,
        String managerNotificationType,
        Integer retryLimit,
        Boolean integrationEnabled,
        Integer retryBaseDelayMinutes,
        String developerName
    ) {
        this.highValueThreshold = highValueThreshold;
        this.defaultManagerUsername = defaultManagerUsername;
        this.defaultQueueDeveloperName = defaultQueueDeveloperName;
        this.managerNotificationType = managerNotificationType;
        this.retryLimit = retryLimit;
        this.integrationEnabled = integrationEnabled == true;
        this.retryBaseDelayMinutes = retryBaseDelayMinutes;
        this.developerName = developerName;
    }

    public static BankCrmSettings fromMetadata(Bank_CRM_Settings__mdt record) {
        if (record == null) {
            throw new BankCrmException('Bank CRM settings metadata record is required.');
        }
        return new BankCrmSettings(
            record.HighValueThreshold__c,
            record.DefaultManagerUsername__c,
            record.DefaultQueueDeveloperName__c,
            record.ManagerNotificationType__c,
            record.RetryLimit__c == null ? null : Integer.valueOf(record.RetryLimit__c),
            record.IntegrationEnabled__c,
            record.RetryBaseDelayMinutes__c == null
                ? null
                : Integer.valueOf(record.RetryBaseDelayMinutes__c),
            record.DeveloperName
        );
    }
}
