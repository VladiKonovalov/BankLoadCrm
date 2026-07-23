@IsTest
private class BankCrmSettingsProviderTest {
    @IsTest
    static void getSettings_returnsDefaultThreshold() {
        BankCrmSettingsProvider.clearCache();
        BankCrmSettings settings = BankCrmSettingsProvider.getSettings();

        System.assertEquals(250000, settings.highValueThreshold);
        System.assertEquals(false, settings.integrationEnabled);
        System.assertEquals('Bank_CRM_Default_Manager', settings.defaultQueueDeveloperName);
        System.assertEquals('High_Value_Loan_Review', settings.managerNotificationType);
        System.assertEquals(3, settings.retryLimit);
        System.assertEquals(15, settings.retryBaseDelayMinutes);
        System.assertEquals('Default', settings.developerName);
    }

    @IsTest
    static void getSettings_cachesWithinTransaction() {
        BankCrmSettingsProvider.clearCache();
        BankCrmSettings first = BankCrmSettingsProvider.getSettings();
        BankCrmSettings second = BankCrmSettingsProvider.getSettings();
        System.assert(
            first === second,
            'Provider should return the same cached instance within a transaction'
        );
    }

    @IsTest
    static void setTestOverride_replacesCmdtValues() {
        BankCrmSettingsProvider.clearCache();
        BankCrmSettings overrideSettings = BankCrmTestDataFactory.buildSettings(999999);
        BankCrmSettingsProvider.setTestOverride(overrideSettings);

        BankCrmSettings settings = BankCrmSettingsProvider.getSettings();
        System.assertEquals(999999, settings.highValueThreshold);
        System.assertEquals(false, settings.integrationEnabled);
    }
}
