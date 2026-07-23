/**
 * Generates and propagates correlation identifiers across LWC, Apex, Flow, and integration.
 */
public with sharing class CorrelationIdUtil {
    private static String currentCorrelationId;

    public static String newId() {
        Blob key = Crypto.generateAesKey(128);
        String hex = EncodingUtil.convertToHex(key);
        return hex.substring(0, 8) +
            '-' +
            hex.substring(8, 12) +
            '-' +
            hex.substring(12, 16) +
            '-' +
            hex.substring(16, 20) +
            '-' +
            hex.substring(20, 32);
    }

    public static String currentOrNew() {
        if (String.isBlank(currentCorrelationId)) {
            currentCorrelationId = newId();
        }
        return currentCorrelationId;
    }

    public static void setCurrent(String correlationId) {
        currentCorrelationId = correlationId;
    }

    @TestVisible
    private static void clearForTest() {
        currentCorrelationId = null;
    }
}
