package com.makeid.makeidlockdemo.ui;

import android.app.Activity;
import android.app.AlertDialog;
import android.widget.*;
import com.makeid.makeidlockdemo.core.InputRules;
import com.makeid.makeidlockdemo.sdk.LockController;
import com.makeid.makeidlockdemo.sdk.OfflineAuthController;
import com.makeid.mkdelectronickeylib.entity.AuthNode;
import com.makeid.mkdelectronickeylib.entity.RuleNode;
import java.util.ArrayList;
import java.util.List;

/** Independent manual authorization editor. Query results never populate any input field. */
public final class OfflineAuthPanel {
    private final Activity activity;
    private final LockController host;
    private final OfflineAuthController controller;
    private final ManualFields fields;
    private final TextView results;
    private final CheckBox zeroLockKey;
    private final List<Button> buttons = new ArrayList<>();
    private AlertDialog confirmation;
    public OfflineAuthPanel(Activity activity, LinearLayout root, LockController host) {
        this.activity = activity; this.host = host;
        TextView note = new TextView(activity);
        note.setText("离线授权 · 本地BLE管理\n仅KY53E/KY53N可用，查询/删除无需锁芯在线。以下授权草稿独立于实时开锁。敏感查询结果不回填，不做云端授权。\nUID/KID/LID各≤16个UTF-8字节；时间填Unix秒，不是毫秒。"); root.addView(note);
        fields = new ManualFields(activity,root);
        fields.add("key","授权通信 · 钥匙侧smSecret（32位HEX，手工输入）",true);
        fields.add("uid","授权UID",false); fields.add("kid","授权KID",false); fields.add("lid","授权LID",false);
        fields.add("pwd","授权锁密码（1～16字节HEX；不足16字节补零）",true);
        fields.add("lockKey","授权记录 · 锁侧smSecret（32位HEX）",true);
        zeroLockKey = new CheckBox(activity);
        zeroLockKey.setText("供应方已确认目标锁允许无密钥：空锁侧字段按全零发送"); root.addView(zeroLockKey);
        fields.add("nid","NID（0～2147483647；查询/删除单条也使用本字段）",false);
        fields.add("start","开始时间Unix秒（0～2147483647）",false);
        fields.add("end","结束时间Unix秒（必须晚于开始）",false);
        fields.add("count","次数（0～65535；0不代表无限次）",false);
        fields.add("enable","启用（显式0或1）",false);
        fields.add("mode","授权模式（0～255；含义须由供应方确认）",false);
        TextView warning = new TextView(activity);
        warning.setText("不提供永久授权/禁用用户等ReserveNode选项：当前96字节编码未发送这些字段。\n查询结果始终隐藏密码/密钥；下发/删除前再次确认。设备ACK不等于实际授权效果验证。"); root.addView(warning);
        results = new TextView(activity); results.setTextIsSelectable(false); root.addView(results);
        controller = new OfflineAuthController(host, text -> results.setText(text));
        addButton(root,"下发人工授权",OfflineAuthController.SEND);
        addButton(root,"按NID查询",OfflineAuthController.QUERY);
        addButton(root,"查询全部",OfflineAuthController.QUERY_ALL);
        addButton(root,"删除指定NID",OfflineAuthController.DELETE);
        addButton(root,"删除当前钥匙全部授权",OfflineAuthController.DELETE_ALL);
        Button clear = new Button(activity); clear.setText("清空授权草稿与查询展示"); root.addView(clear);
        clear.setOnClickListener(v -> { if (!host.busy()) clear(); });
    }
    private void addButton(LinearLayout root,String title,int operation) {
        Button button = new Button(activity); button.setText(title); root.addView(button); buttons.add(button);
        button.setOnClickListener(v -> {
            try {
                host.requireKey();
                final long session = host.session();
                final String key = InputRules.secret(fields.text("key"),"授权通信钥匙侧密钥");
                final int nid = operation == OfflineAuthController.QUERY || operation == OfflineAuthController.DELETE
                        ? InputRules.integer(fields.text("nid"),"NID",0,Integer.MAX_VALUE) : 0;
                final AuthNode draft = operation == OfflineAuthController.SEND ? draft() : null;
                Runnable send = () -> {
                    if (!host.active(session)) { toast("设备会话已经改变，请重新确认"); return; }
                    try { controller.execute(operation,nid,draft,key); }
                    catch (IllegalArgumentException | IllegalStateException error) { toast(error.getMessage()); }
                };
                if (operation == OfflineAuthController.QUERY || operation == OfflineAuthController.QUERY_ALL) { send.run(); return; }
                String scope = draft == null ? operation == OfflineAuthController.DELETE_ALL ? "当前钥匙的全部授权" : "NID="+nid
                        : "KID="+draft.getKid()+"\nLID="+draft.getLid()+"\nNID="+draft.getRuleNode().getNid()+"\n密码编码不足16字节将补零";
                confirmation = new AlertDialog.Builder(activity).setTitle(title).setMessage("当前连接："+host.deviceLabel()+"\n"+scope+"\n请确认实际授权与影响范围。超时/断线不自动重发。")
                        .setNegativeButton("取消",null).setPositiveButton("确认执行",(dialog,which)->send.run()).show();
                confirmation.setOnDismissListener(dialog -> confirmation = null);
            } catch (IllegalArgumentException | IllegalStateException error) { toast(error.getMessage()); }
        });
    }
    private AuthNode draft() {
        AuthNode node = new AuthNode();
        node.setUid(InputRules.identifier(fields.text("uid"),"UID"));
        node.setKid(InputRules.identifier(fields.text("kid"),"KID"));
        node.setLid(InputRules.identifier(fields.text("lid"),"LID"));
        node.setPassword(InputRules.hex(fields.text("pwd"),"授权锁密码",1,16,false));
        String lock = InputRules.hex(fields.text("lockKey"),"授权锁密钥",16,16,zeroLockKey.isChecked());
        node.setLockSmSecret(lock);
        RuleNode rule = new RuleNode();
        rule.setNid(InputRules.integer(fields.text("nid"),"NID",0,Integer.MAX_VALUE));
        long start = InputRules.seconds(fields.text("start"),"开始时间",0,Integer.MAX_VALUE);
        long end = InputRules.seconds(fields.text("end"),"结束时间",0,Integer.MAX_VALUE);
        if (end <= start) throw new IllegalArgumentException("授权结束时间必须晚于开始时间");
        rule.setStartDatetime(start); rule.setEndDatetime(end);
        rule.setCount(InputRules.integer(fields.text("count"),"次数",0,65535));
        rule.setEnable(InputRules.integer(fields.text("enable"),"启用",0,1));
        rule.setAuthMode(InputRules.integer(fields.text("mode"),"授权模式",0,255));
        node.setRuleNode(rule); return node;
    }
    public void refresh() {
        boolean enabled = host.canManageAuth();
        for (Button b : buttons) b.setEnabled(enabled);
        fields.enabled(!host.busy()); zeroLockKey.setEnabled(!host.busy());
    }
    public void clear() { if (confirmation != null) confirmation.dismiss(); fields.clearAll(); zeroLockKey.setChecked(false); controller.clear(); }
    private void toast(String message) { Toast.makeText(activity,message,Toast.LENGTH_LONG).show(); }
}
