@IsTest
private class BankCrmExceptionTest {
    @IsTest
    static void hierarchy_canBeThrownAndCaughtByType() {
        try {
            throw new BankCrmException.ValidationException('validation');
        } catch (BankCrmException.ValidationException ex) {
            System.assertEquals('validation', ex.getMessage());
        }

        try {
            throw new BankCrmException.AuthorizationException('auth');
        } catch (BankCrmException.AuthorizationException ex) {
            System.assertEquals('auth', ex.getMessage());
        }

        try {
            throw new BankCrmException.MandatoryAutomationException('mandatory');
        } catch (BankCrmException.MandatoryAutomationException ex) {
            System.assertEquals('mandatory', ex.getMessage());
        }

        try {
            throw new BankCrmException.IntegrationException('integration');
        } catch (BankCrmException.IntegrationException ex) {
            System.assertEquals('integration', ex.getMessage());
        }

        try {
            throw new BankCrmException('base');
        } catch (BankCrmException ex) {
            System.assertEquals('base', ex.getMessage());
        }
    }
}
