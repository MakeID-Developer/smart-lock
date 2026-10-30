package com.makeid.makeidlockdemo.core;

public enum Transport {
    NFC("手机 NFC"), READER("BLE读写器 / KY电子钥匙"), BLE("直连BLE锁（机械关锁）"), USB("USB锁");
    public final String label;
    Transport(String label) { this.label = label; }
    public boolean supportsClose() { return this != BLE; }
    public boolean needsBluetooth() { return this == READER || this == BLE; }
    @Override public String toString() { return label; }
}
