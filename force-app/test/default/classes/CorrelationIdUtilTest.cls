@IsTest
private class CorrelationIdUtilTest {
    @IsTest
    static void newId_returnsUniqueNonBlankValues() {
        CorrelationIdUtil.clearForTest();
        String first = CorrelationIdUtil.newId();
        String second = CorrelationIdUtil.newId();

        System.assert(String.isNotBlank(first), 'Correlation Id must be non-blank');
        System.assert(String.isNotBlank(second), 'Correlation Id must be non-blank');
        System.assertNotEquals(first, second, 'Generated Ids should differ');
        System.assertEquals(36, first.length(), 'Expected UUID-like length');
    }

    @IsTest
    static void currentOrNew_reusesCurrentValue() {
        CorrelationIdUtil.clearForTest();
        String first = CorrelationIdUtil.currentOrNew();
        String second = CorrelationIdUtil.currentOrNew();
        System.assertEquals(first, second, 'currentOrNew should reuse the transaction value');
    }

    @IsTest
    static void setCurrent_overridesValue() {
        CorrelationIdUtil.clearForTest();
        CorrelationIdUtil.setCurrent('fixed-correlation-id');
        System.assertEquals('fixed-correlation-id', CorrelationIdUtil.currentOrNew());
    }
}
