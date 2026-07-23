/**
 * Centralizes strict greater-than high-value threshold and crossing semantics.
 */
public with sharing class CurrencyThresholdUtil {
    public static Boolean isAboveThreshold(Decimal amount, Decimal threshold) {
        if (amount == null || threshold == null) {
            return false;
        }
        return amount > threshold;
    }

    /**
     * Crossing is true when the new amount is above threshold and the old amount
     * was at or below threshold (or null, e.g. insert treated as a cross).
     */
    public static Boolean crossedThreshold(Decimal oldAmount, Decimal newAmount, Decimal threshold) {
        if (!isAboveThreshold(newAmount, threshold)) {
            return false;
        }
        if (oldAmount == null) {
            return true;
        }
        return !isAboveThreshold(oldAmount, threshold);
    }
}
