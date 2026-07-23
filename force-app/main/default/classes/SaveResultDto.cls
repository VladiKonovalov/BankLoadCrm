/**
 * Stable LWC save response containing success, IDs, and structured failures.
 */
public with sharing class SaveResultDto {
    @AuraEnabled
    public Boolean success { get; set; }

    @AuraEnabled
    public Id loanRequestId { get; set; }

    @AuraEnabled
    public String correlationId { get; set; }

    @AuraEnabled
    public List<ValidationFailure> errors { get; set; }

    public SaveResultDto() {
        this.success = false;
        this.errors = new List<ValidationFailure>();
    }

    public static SaveResultDto success(Id loanRequestId, String correlationId) {
        SaveResultDto result = new SaveResultDto();
        result.success = true;
        result.loanRequestId = loanRequestId;
        result.correlationId = correlationId;
        return result;
    }

    public static SaveResultDto failure(
        String correlationId,
        List<ValidationFailure> failures
    ) {
        SaveResultDto result = new SaveResultDto();
        result.success = false;
        result.correlationId = correlationId;
        result.errors = failures == null ? new List<ValidationFailure>() : failures;
        return result;
    }
}
