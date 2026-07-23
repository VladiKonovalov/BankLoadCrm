@IsTest
private class SanitizedMessageUtilTest {
    @IsTest
    static void sanitize_redactsBearerToken() {
        String raw = 'Call failed bearer abc.def.ghi-123 payload omitted';
        String sanitized = SanitizedMessageUtil.sanitize(raw);
        System.assert(sanitized.contains('[REDACTED]'), 'Token should be redacted');
        System.assert(!sanitized.contains('abc.def.ghi-123'), 'Raw token must not remain');
    }

    @IsTest
    static void sanitize_redactsApiKeyPattern() {
        String raw = 'Upstream error api_key=supersecretvalue remaining text';
        String sanitized = SanitizedMessageUtil.sanitize(raw);
        System.assert(sanitized.contains('[REDACTED]'));
        System.assert(!sanitized.contains('supersecretvalue'));
    }

    @IsTest
    static void sanitize_truncatesLongMessages() {
        String raw = 'x'.repeat(4500);
        String sanitized = SanitizedMessageUtil.sanitize(raw);
        System.assertEquals(4000, sanitized.length(), 'Messages must truncate at 4000');
    }

    @IsTest
    static void sanitize_null_returnsNull() {
        System.assertEquals(null, SanitizedMessageUtil.sanitize(null));
    }
}
