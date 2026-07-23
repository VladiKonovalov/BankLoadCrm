/**
 * Redacts secrets/token-like patterns and truncates text before audit/error persistence.
 */
public with sharing class SanitizedMessageUtil {
    private static final Integer MAX_LENGTH = 4000;

    private static final List<String> TOKEN_PATTERNS = new List<String>{
        '(?i)(bearer\\s+)[a-z0-9\\-._~+/]+=*',
        '(?i)(authorization\\s*[:=]\\s*)[^\\s,;]+',
        '(?i)(api[_-]?key\\s*[:=]\\s*)[^\\s,;]+',
        '(?i)(access[_-]?token\\s*[:=]\\s*)[^\\s,;]+',
        '(?i)(secret\\s*[:=]\\s*)[^\\s,;]+',
        '(?i)(password\\s*[:=]\\s*)[^\\s,;]+',
        '(?i)(session[_-]?id\\s*[:=]\\s*)[^\\s,;]+'
    };

    public static String sanitize(String raw) {
        if (raw == null) {
            return null;
        }
        String sanitized = raw;
        for (String pattern : TOKEN_PATTERNS) {
            sanitized = sanitized.replaceAll(pattern, '$1[REDACTED]');
        }
        if (sanitized.length() > MAX_LENGTH) {
            sanitized = sanitized.substring(0, MAX_LENGTH);
        }
        return sanitized;
    }
}
