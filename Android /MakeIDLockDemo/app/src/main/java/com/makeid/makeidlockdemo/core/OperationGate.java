package com.makeid.makeidlockdemo.core;

/** Main-thread owned. Token uniqueness prevents old callbacks from completing a new operation. */
public final class OperationGate {
    private long sequence;
    private long active;
    public long begin() {
        if (active != 0) throw new IllegalStateException("上一项操作尚未结束");
        active = ++sequence;
        return active;
    }
    public boolean isBusy() { return active != 0; }
    public boolean isCurrent(long token) { return active != 0 && active == token; }
    public boolean finish(long token) {
        if (!isCurrent(token)) return false;
        active = 0;
        return true;
    }
    public void invalidate() { ++sequence; active = 0; }
}
