package com.makeid.makeidlockdemo.core;

public final class Redactor {
    private Redactor() { }
    public static String safe(String text) {
        if (text == null) return "未知错误";
        return text.replaceAll("(?i)(password|pwd|appsecret|smsecret|secret|key)\\s*[=:：]\\s*[^\\s,;]+", "$1=***")
                .replaceAll("(?i)(?<![0-9a-f])[0-9a-f]{8,}(?![0-9a-f])", "***");
    }
}
