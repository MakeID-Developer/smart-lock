package com.makeid.makeidlockdemo.core;

import org.junit.Test;
import static org.junit.Assert.*;

/** Run with the host's tests only after AARs are supplied and compilation is explicitly requested. */
public class DemoRulesTest {
    @Test public void bleUsesMechanicalClosingButUsbHasAnApi() {
        assertFalse(Transport.BLE.supportsClose());
        assertTrue(Transport.USB.supportsClose());
        assertTrue(Transport.NFC.supportsClose());
    }
    @Test public void hexDoesNotSilentlyTruncateOrAcceptSeparators() {
        assertEquals("AABB", InputRules.hex("aabb", "密码", 2, 2, false));
        expectInvalid(() -> InputRules.hex("AA BB", "密码", 2, 2, false));
        expectInvalid(() -> InputRules.hex("AABBC", "密码", 1, 16, false));
        expectInvalid(() -> InputRules.hex("AABBCC", "密码", 2, 2, false));
    }
    @Test public void utf8LimitIsBytesNotCharacters() {
        assertEquals("A-01", InputRules.identifier("A-01", "UID"));
        expectInvalid(() -> InputRules.identifier("汉字测试超过十六字节", "UID"));
    }
    @Test public void explicitZeroIsValidButOverflowAndMissingAreNot() {
        assertEquals(0, InputRules.integer("0", "NID", 0, Integer.MAX_VALUE));
        expectInvalid(() -> InputRules.integer("2147483648", "NID", 0, Integer.MAX_VALUE));
        expectInvalid(() -> InputRules.integer("", "NID", 0, Integer.MAX_VALUE));
        expectInvalid(() -> InputRules.integer("65536", "次数", 0, 65535));
    }
    @Test public void oldSessionAndDuplicateResultsAreIgnored() {
        OperationGate gate = new OperationGate();
        long old = gate.begin();
        assertTrue(gate.isBusy());
        assertTrue(gate.finish(old));
        assertFalse(gate.finish(old));
        long current = gate.begin();
        assertFalse(gate.finish(old));
        gate.invalidate();
        assertFalse(gate.finish(current));
        assertFalse(gate.isBusy());
    }
    @Test public void lateTimeoutCannotOverrideNewTransaction() {
        OperationGate gate = new OperationGate();
        long first = gate.begin();
        assertTrue(gate.finish(first));
        long second = gate.begin();
        assertFalse(gate.isCurrent(first));
        assertTrue(gate.isCurrent(second));
    }
    @Test public void secretsInSdkErrorsAreRedacted() {
        String message = "pwd=11223344 secret=00112233445566778899aabbccddeeff";
        String safe = Redactor.safe(message);
        assertFalse(safe.contains("11223344"));
        assertFalse(safe.contains("00112233445566778899aabbccddeeff"));
    }
    private static void expectInvalid(Runnable action) {
        try { action.run(); fail("Must reject invalid manual input"); }
        catch (IllegalArgumentException expected) { }
    }
}
