/**
 * Loads and caches Bank_CRM_Settings__mdt Default once per transaction.
 */
public with sharing class BankCrmSettingsProvider {
    private static final String DEFAULT_DEVELOPER_NAME = 'Default';

    private static BankCrmSettings cachedSettings;
    @TestVisible
    private static BankCrmSettings testOverride;

    public static BankCrmSettings getSettings() {
        if (testOverride != null) {
            return testOverride;
        }
        if (cachedSettings == null) {
            cachedSettings = loadDefaultSettings();
        }
        return cachedSettings;
    }

    private static BankCrmSettings loadDefaultSettings() {
        List<Bank_CRM_Settings__mdt> records = [
            SELECT
                DeveloperName,
                HighValueThreshold__c,
                DefaultManagerUsername__c,
                DefaultQueueDeveloperName__c,
                ManagerNotificationType__c,
                RetryLimit__c,
                IntegrationEnabled__c,
                RetryBaseDelayMinutes__c
            FROM Bank_CRM_Settings__mdt
            WHERE DeveloperName = :DEFAULT_DEVELOPER_NAME
            LIMIT 1
        ];
        if (records.isEmpty()) {
            throw new BankCrmException(
                'Bank_CRM_Settings__mdt record "' + DEFAULT_DEVELOPER_NAME + '" was not found.'
            );
        }
        return BankCrmSettings.fromMetadata(records[0]);
    }

    @TestVisible
    private static void setTestOverride(BankCrmSettings settings) {
        testOverride = settings;
        cachedSettings = null;
    }

    @TestVisible
    private static void clearCache() {
        cachedSettings = null;
        testOverride = null;
    }
}
