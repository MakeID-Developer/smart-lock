package com.makeid.makeidlockdemo.sdk;

import android.os.Handler;
import android.os.Looper;
import com.makeid.makeidlockdemo.core.InputRules;
import com.makeid.mkdelectronickeylib.entity.AuthNode;
import com.makeid.mkdelectronickeylib.entity.ManageOfflineAuthResult;
import com.makeid.mkdelectronickeylib.listener.OnManageOfflineAuthListener;
import com.makeid.mkdelectronickeylib.listener.OnSendOfflineAuthListener;
import java.util.List;

/** Shares the parent's SDK, transaction gate, and session. Never reconnects or retrieves secrets. */
public final class OfflineAuthController {
    public interface View { void results(String summary); }
    public static final int SEND = 0, QUERY = 1, QUERY_ALL = 2, DELETE = 3, DELETE_ALL = 4;
    private final LockController host;
    private final View view;
    private final Handler main = new Handler(Looper.getMainLooper());
    private Runnable stalled;
    public OfflineAuthController(LockController host, View view) { this.host = host; this.view = view; }
    public void clear() { if (stalled != null) main.removeCallbacks(stalled); stalled = null; view.results(""); }
    public void execute(int operation, int nid, AuthNode draft, String manualKeySecret) {
        host.requireKey();
        final String key = InputRules.secret(manualKeySecret, "授权通信的钥匙侧密钥");
        final long session = host.session();
        clear();
        host.begin(operation == SEND ? "下发离线授权" : operation == QUERY_ALL ? "查询全部离线授权" : "管理离线授权", operation == QUERY_ALL ? 90000 : 30000, token -> {
            if (operation == SEND) {
                if (draft == null) throw new IllegalArgumentException("请填写人工授权草稿");
                host.sdk().sendElectronicKeyOfflineAuth(draft, key, new OnSendOfflineAuthListener() {
                    @Override public void onSendResult(boolean success) { host.accept(session, token, success ? "钥匙确认收到授权，实际使用效果需另行核验" : "设备拒绝授权下发", success); }
                    @Override public void onFail(int code, String message) { host.accept(session, token, "授权下发失败 " + code + ":" + message, false); }
                });
                return;
            }
            OnManageOfflineAuthListener listener = new OnManageOfflineAuthListener() {
                private boolean failed;
                @Override public void onManageOfflineAuthResult(ManageOfflineAuthResult result) {
                    main.post(() -> {
                        if (!host.current(session, token) || failed) return;
                        if (result == null || result.getOperationType() != operation || !result.isSuccess()) {
                            failed = true;
                            cancelStall();
                            if (operation == QUERY_ALL || result == null || result.getOperationType() != operation)
                                host.invalidateUnknown("授权响应不匹配/查询流失败，已终止旧会话，勿直接重发");
                            else host.finish(token, "授权管理返回失败，未修改界面记录", false);
                            return;
                        }
                        if (operation == QUERY_ALL) { resetStall(session, token); return; }
                        if (operation == QUERY) {
                            view.results(result.getAuthNode() == null ? "本次未返回授权节点" : summary(result.getAuthNode()));
                        } else view.results("设备确认删除；请手动重新查询核实，不自动重发。");
                        host.finish(token, result.getAuthNode() == null && operation == QUERY ? "查询未返回节点" : "授权管理返回成功", true);
                    });
                }
                @Override public void onManageOfflineAuthProgress(int current, int total) {
                    main.post(() -> {
                        if (!host.current(session, token) || operation != QUERY_ALL || failed) return;
                        resetStall(session, token);
                        host.progress(session, token, "授权查询进度 " + current + "/" + total);
                    });
                }
                @Override public void onManageOfflineAuthFinish(List<AuthNode> nodes) {
                    main.post(() -> {
                        if (!host.current(session, token) || operation != QUERY_ALL || failed) return;
                        cancelStall();
                        StringBuilder text = new StringBuilder("授权条数=" + (nodes == null ? 0 : nodes.size()) + "\n密码和锁密钥始终隐藏；不提供回填开锁。\n");
                        if (nodes != null) {
                            int shown = Math.min(nodes.size(), 200);
                            for (int i = 0; i < shown; i++) text.append(summary(nodes.get(i))).append("\n\n");
                            if (nodes.size() > shown) text.append("界面仅展示前200条，请按NID查询其他记录。");
                        }
                        view.results(text.toString());
                        host.finish(token, "全部查询结束（空列表也为正常结果）", true);
                    });
                }
                @Override public void onManageOfflineAuthError(int code, String message) {
                    main.post(() -> {
                        if (!host.current(session, token)) return;
                        failed = true;
                        cancelStall();
                        // The SDK exposes parsing errors here too. A device's remaining stream is not cancelled.
                        host.invalidateUnknown("授权管理错误 " + code + ":" + message + "；已关闭旧会话防止迟到包混入下一事务");
                    });
                }
            };
            if (operation == QUERY) host.sdk().queryElectronicKeyOfflineAuth(nid, key, listener);
            else if (operation == QUERY_ALL) { resetStall(session, token); host.sdk().queryAllElectronicKeyOfflineAuth(key, listener); }
            else if (operation == DELETE) host.sdk().deleteElectronicKeyOfflineAuth(nid, key, listener);
            else if (operation == DELETE_ALL) host.sdk().deleteAllElectronicKeyOfflineAuth(key, listener);
            else throw new IllegalArgumentException("未知授权操作");
        });
    }
    private void resetStall(long session, long token) {
        cancelStall();
        stalled = () -> { if (host.current(session, token)) host.invalidateUnknown("查询全部20秒无进展，已关闭旧会话"); };
        main.postDelayed(stalled, 20000);
    }
    private void cancelStall() { if (stalled != null) main.removeCallbacks(stalled); stalled = null; }
    private static String summary(AuthNode node) {
        if (node == null) return "空节点";
        String text = "UID=" + display(node.getUid()) + " / KID=" + display(node.getKid()) + " / LID=" + display(node.getLid());
        if (node.getRuleNode() != null) text += "\nNID=" + node.getRuleNode().getNid() + ", 次数=" + node.getRuleNode().getCount()
                + ", 启用=" + node.getRuleNode().getEnable() + ", 模式=" + node.getRuleNode().getAuthMode()
                + "\nUnix秒=" + node.getRuleNode().getStartDatetime() + " ～ " + node.getRuleNode().getEndDatetime();
        // Never call getPassword()/getLockSmSecret() on a returned node or serialize the object.
        return text + "\n密码=***，锁密钥=***";
    }
    private static String display(String text) { return text == null ? "" : text.replaceAll("[\\r\\n\\t]", " "); }
}
