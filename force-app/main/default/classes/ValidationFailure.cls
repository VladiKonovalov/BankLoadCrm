/**
 * User-safe field-level validation failure for LWC responses.
 */
public with sharing class ValidationFailure {
    @AuraEnabled
    public String fieldApiName { get; set; }

    @AuraEnabled
    public String message { get; set; }

    public ValidationFailure() {
    }

    public ValidationFailure(String fieldApiName, String message) {
        this.fieldApiName = fieldApiName;
        this.message = message;
    }
}
