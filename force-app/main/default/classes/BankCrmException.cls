/**
 * Base domain exception with typed subtypes for validation, authorization,
 * mandatory automation, and integration failures.
 */
public virtual class BankCrmException extends Exception {
    public class ValidationException extends BankCrmException {
    }

    public class AuthorizationException extends BankCrmException {
    }

    public class MandatoryAutomationException extends BankCrmException {
    }

    public class IntegrationException extends BankCrmException {
    }
}
