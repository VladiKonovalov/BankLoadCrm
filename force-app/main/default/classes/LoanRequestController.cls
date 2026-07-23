/**
 * LWC create API for loan requests. Enforces sharing, CRUD/FLS, and restricted DTOs.
 */
public with sharing class LoanRequestController {
    @AuraEnabled
    public static SaveResultDto saveLoanRequest(LoanRequestDto dto) {
        String correlationId = CorrelationIdUtil.currentOrNew();
        try {
            ApexSecurityHelper.assertCreateable(LoanRequest__c.SObjectType);

            List<ValidationFailure> failures =
                LoanRequestValidationService.validateForLwcCreate(dto);
            if (!failures.isEmpty()) {
                return SaveResultDto.failure(correlationId, failures);
            }

            LoanRequest__c record = dto.toSObject();
            stampSubmissionDateIfNeeded(record);

            // Object CRUD is asserted above; skip field strip so Apex-owned stamps
            // (e.g. SubmissionDate__c) are not removed when the user lacks field edit FLS.
            LoanRequestRepository.DmlOptions options = new LoanRequestRepository.DmlOptions();
            options.enforceSecurity = false;

            List<Database.SaveResult> results = LoanRequestRepository.insertLoans(
                new List<LoanRequest__c>{ record },
                options
            );
            if (results.isEmpty() || !results[0].isSuccess()) {
                return SaveResultDto.failure(
                    correlationId,
                    new List<ValidationFailure>{
                        new ValidationFailure(
                            null,
                            System.Label.Bank_CRM_Generic_Save_Error
                        )
                    }
                );
            }

            return SaveResultDto.success(results[0].getId(), correlationId);
        } catch (BankCrmException.AuthorizationException ex) {
            throwAura(System.Label.Bank_CRM_Access_Denied);
            return null;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            ApplicationErrorService.ErrorContext errorCtx =
                new ApplicationErrorService.ErrorContext(
                    'LoanRequestController',
                    'saveLoanRequest'
                );
            errorCtx.correlationId = correlationId;
            try {
                ApplicationErrorService.log(ex, errorCtx);
            } catch (Exception ignore) {
                // Best-effort logging only.
            }
            throwAura(System.Label.Bank_CRM_Generic_Save_Error);
            return null;
        }
    }

    private static void stampSubmissionDateIfNeeded(LoanRequest__c record) {
        if (record == null) {
            return;
        }
        if (
            String.isNotBlank(record.LoanStatus__c)
            && record.LoanStatus__c != 'Draft'
            && record.SubmissionDate__c == null
        ) {
            record.SubmissionDate__c = System.now();
        }
    }

    private static void throwAura(String message) {
        throw new AuraHandledException(message);
    }
}
