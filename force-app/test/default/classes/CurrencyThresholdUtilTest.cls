@IsTest
private class CurrencyThresholdUtilTest {
    private static final Decimal THRESHOLD = 250000;

    @IsTest
    static void isAboveThreshold_exactThreshold_isFalse() {
        System.assertEquals(
            false,
            CurrencyThresholdUtil.isAboveThreshold(THRESHOLD, THRESHOLD),
            'Exact threshold must not be above'
        );
    }

    @IsTest
    static void isAboveThreshold_oneAbove_isTrue() {
        System.assertEquals(
            true,
            CurrencyThresholdUtil.isAboveThreshold(THRESHOLD + 1, THRESHOLD),
            'Amount one above threshold must be high value'
        );
    }

    @IsTest
    static void isAboveThreshold_nulls_areSafe() {
        System.assertEquals(false, CurrencyThresholdUtil.isAboveThreshold(null, THRESHOLD));
        System.assertEquals(false, CurrencyThresholdUtil.isAboveThreshold(THRESHOLD, null));
        System.assertEquals(false, CurrencyThresholdUtil.isAboveThreshold(null, null));
    }

    @IsTest
    static void crossedThreshold_insertAbove_isTrue() {
        System.assertEquals(
            true,
            CurrencyThresholdUtil.crossedThreshold(null, 300000, THRESHOLD),
            'Insert above threshold counts as a crossing'
        );
    }

    @IsTest
    static void crossedThreshold_raiseAcross_isTrue() {
        System.assertEquals(
            true,
            CurrencyThresholdUtil.crossedThreshold(200000, 300000, THRESHOLD)
        );
    }

    @IsTest
    static void crossedThreshold_alreadyAbove_isFalse() {
        System.assertEquals(
            false,
            CurrencyThresholdUtil.crossedThreshold(300000, 400000, THRESHOLD),
            'Already above is not a new crossing'
        );
    }

    @IsTest
    static void crossedThreshold_exactThenStay_isFalse() {
        System.assertEquals(
            false,
            CurrencyThresholdUtil.crossedThreshold(THRESHOLD, THRESHOLD, THRESHOLD)
        );
    }

    @IsTest
    static void crossedThreshold_lowerBelow_isFalse() {
        System.assertEquals(
            false,
            CurrencyThresholdUtil.crossedThreshold(300000, 100000, THRESHOLD)
        );
    }
}
