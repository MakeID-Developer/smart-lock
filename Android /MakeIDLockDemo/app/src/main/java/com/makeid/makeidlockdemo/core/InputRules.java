package com.makeid.makeidlockdemo.core;

import java.nio.charset.StandardCharsets;
import java.util.Locale;

public final class InputRules {
    private InputRules() { }
    public static String required(String value, String label) {
        String result = value == null ? "" : value.trim();
        if (result.isEmpty()) throw new IllegalArgumentException(label + "不能为空");
        return result;
    }
    public static String hex(String value, String label, int minBytes, int maxBytes, boolean optional) {
        String result = value == null ? "" : value.trim();
        if (optional && result.isEmpty()) return "";
        if (!result.matches("[0-9a-fA-F]+") || (result.length() & 1) != 0
                || result.length() < minBytes * 2 || result.length() > maxBytes * 2)
            throw new IllegalArgumentException(label + "需为" + minBytes + "～" + maxBytes + "字节HEX，不带空格/0x");
        return result.toUpperCase(Locale.ROOT);
    }
    public static String secret(String value, String label) { return hex(value, label, 16, 16, false); }
    public static String identifier(String value, String label) {
        String result = required(value, label);
        if (result.getBytes(StandardCharsets.UTF_8).length > 16)
            throw new IllegalArgumentException(label + "的UTF-8编码不能超过16字节");
        return result;
    }
    public static int integer(String value, String label, int min, int max) {
        long number = seconds(value, label, min, max);
        return (int) number;
    }
    public static long seconds(String value, String label, long min, long max) {
        String result = required(value, label);
        if (!result.matches("[0-9]+")) throw new IllegalArgumentException(label + "需为非负十进制整数");
        try {
            long number = Long.parseLong(result);
            if (number < min || number > max) throw new NumberFormatException();
            return number;
        } catch (NumberFormatException error) {
            throw new IllegalArgumentException(label + "范围为" + min + "～" + max);
        }
    }
}
