package com.makeid.makeidlockdemo.config;

/**
 * Fixed Android demo SDK authorization, embedded at the owner's explicit request.
 * This is not a device password or a key-side/lock-side smSecret.
 * Source/APK recipients can extract these values: confirm redistribution permission before release.
 * Never print these constants in the UI, SDK diagnostics, or application logs.
 */
public final class SdkCredentials {
    public static final String APPLICATION_ID = "com.makeid.makeidlockdemo";
    public static final String APP_ID = "6c63b19f5009f5e474a6400b17224e1f";
    public static final String APP_SECRET = "345690287454118c008b7ca63b7266fb2c33e530";

    private SdkCredentials() { }
}
