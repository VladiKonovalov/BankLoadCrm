/**
 * Cacheable LWC read API for summary display fields only.
 */
public with sharing class LoanRequestReadController {
    @AuraEnabled(cacheable=true)
    public static LoanRequestDto getLoanRequest(Id loanRequestId) {
        if (loanRequestId == null) {
            throwAura(System.Label.Bank_CRM_Access_Denied);
            return null;
        }

        try {
            ApexSecurityHelper.assertReadable(LoanRequest__c.SObjectType);

            List<LoanRequest__c> records = LoanRequestRepository.getByIds(
                new Set<Id>{ loanRequestId }
            );
            if (records.isEmpty()) {
                throwAura(System.Label.Bank_CRM_Access_Denied);
                return null;
            }

            List<SObject> stripped = ApexSecurityHelper.stripInaccessible(
                AccessType.READABLE,
                new List<SObject>{ records[0] }
            );
            LoanRequest__c accessible = (LoanRequest__c) stripped[0];
            return toDisplayDto(accessible);
        } catch (BankCrmException.AuthorizationException ex) {
            throwAura(System.Label.Bank_CRM_Access_Denied);
            return null;
        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            ApplicationErrorService.ErrorContext errorCtx =
                new ApplicationErrorService.ErrorContext(
                    'LoanRequestReadController',
                    'getLoanRequest'
                );
            errorCtx.loanRequestId = loanRequestId;
            try {
                ApplicationErrorService.log(ex, errorCtx);
            } catch (Exception ignore) {
                // Best-effort logging only.
            }
            throwAura(System.Label.Bank_CRM_Access_Denied);
            return null;
        }
    }

    private static LoanRequestDto toDisplayDto(LoanRequest__c record) {
        LoanRequestDto dto = LoanRequestDto.fromSObject(record);
        // Ensure response contract never carries write-side identifiers beyond display needs.
        if (dto != null) {
            dto.customerId = null;
        }
        return dto;
    }

    private static void throwAura(String message) {
        throw new AuraHandledException(message);
    }
}
