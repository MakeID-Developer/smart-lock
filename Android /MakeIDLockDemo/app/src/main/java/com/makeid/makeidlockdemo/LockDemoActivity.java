package com.makeid.makeidlockdemo;

import android.app.Activity;
import android.app.AlertDialog;
import android.nfc.NfcAdapter;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.WindowManager;
import android.widget.*;
import com.makeid.blelibrary.bean.Device;
import com.makeid.makeidlockdemo.core.*;
import com.makeid.makeidlockdemo.sdk.LockController;
import com.makeid.makeidlockdemo.ui.*;
import java.util.*;
import com.makeid.makeidlockdemo.databinding.ActivityLockDemoBinding;

/** Simplified SDK reference UI; no automatic write operation, saved credential, or cross-page SDK owner. */
public final class LockDemoActivity extends Activity implements LockController.View {
    private final Handler main = new Handler(Looper.getMainLooper());
    private LockController controller;
    private PermissionHelper permissions;
    private ManualFields fields;
    private ManualFields keyFields;
    private OfflineAuthPanel authPanel;
    private Spinner modes;
    private TextView status;
    private TextView logView;
    private ScrollView logScroll;
    private LinearLayout keySection;
    private LinearLayout authSection;
    private final List<Button> queryButtons = new ArrayList<>();
    private final List<Button> keyButtons = new ArrayList<>();
    private Button initButton, scanButton, closeLockButton, openLockButton, countButton;
    private final Deque<String> logs = new ArrayDeque<>();
    private final List<Device> scanned = new ArrayList<>();
    private final List<String> scanLabels = new ArrayList<>();
    private ArrayAdapter<String> scanAdapter;
    private AlertDialog scanDialog;
    private AlertDialog confirmation;
    private NfcAdapter nfc;
    private long nfcGeneration;
    private boolean nfcEnabled;
    private boolean closed;
    private final Runnable heartbeatRefresh = new Runnable() {
        @Override public void run() { if (!closed) { changed(); main.postDelayed(this,1000); } }
    };

    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        permissions = new PermissionHelper(this);
        ActivityLockDemoBinding binding = ActivityLockDemoBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());
        LinearLayout root = binding.content;
        logView = binding.logView;
        logScroll = binding.logScroll;
        binding.clearLog.setOnClickListener(v -> { logs.clear(); logView.setText(""); });
        text(root,"智能锁 / 电子钥匙",25);
        text(root,"单会话 · 人工凭证 · 无网络\n查询与授权只在用户点击后发送。切后台/换模式会关闭会话并清空输入。",14);
        modes = new Spinner(this);
        modes.setAdapter(new ArrayAdapter<>(this,android.R.layout.simple_spinner_dropdown_item,Transport.values())); root.addView(modes);
        fields = new ManualFields(this,root);
        text(root,"SDK鉴权已内置，无需输入；当前包名："+getPackageName()+"。锁密码及两侧设备密钥仍需手工填写。",14);
        initButton = button(root,"初始化当前连接方式（内置鉴权）",()->{
            final Transport mode = selected();
            permissions.run(mode,()-> safe(()->{
                disableNfc();
                controller.initialize(mode);
                if (mode == Transport.NFC) enableNfc();
            }));
        });
        status = text(root,"未初始化",15);
        button(root,"断开并清除整个会话",()->{ disableNfc(); permissions.cancel(); controller.close(); fields.clearAll(); });
        scanButton = button(root,"扫描并手动选择BLE设备",this::scan);
        text(root,"实时操作参数（与授权草稿独立）",19);
        fields.add("uid","操作UID（UTF-8最多16字节）",false);
        fields.add("expected","预期目标锁SN（先查询/看心跳，再手工核对输入）",false);
        fields.add("pwd","锁密码HEX（KY53E为8位HEX，其他锁型按协议）",true);
        fields.add("lockKey","锁侧smSecret（加密锁需要32位HEX；BLE/USB不使用）",true);
        queryButtons.add(button(root,"读取基础信息",()->controller.query("基础信息",fields.text("uid"))));
        queryButtons.add(button(root,"读取状态 / 电量",()->controller.query("状态电量",fields.text("uid"))));
        queryButtons.add(button(root,"读取锁固件版本",()->controller.query("版本",fields.text("uid"))));
        countButton = button(root,"读取开锁次数（KY53E不支持此通用接口）",()->controller.query("开锁次数",fields.text("uid")));
        openLockButton = button(root,"人工确认后开锁",()->confirmLock(true));
        closeLockButton = button(root,"人工确认后接口关锁（直连BLE无此能力）",()->confirmLock(false));
        text(root,"直连BLE锁请通过机械结构关锁；本Demo不调用其关锁API。USB仅连接一台受支持锁/适配器，系统授权成功不等于锁具身份已确认。",14);
        keySection = column(); root.addView(keySection);
        text(keySection,"电子钥匙信息与时间",19);
        keyFields = new ManualFields(this,keySection);
        keyFields.add("keySecret","实时钥匙侧smSecret（仅钥匙业务使用，32位HEX）",true);
        keyFields.add("time","同步Unix秒（留空则使用手机当前时间）",false);
        keyButtons.add(button(keySection,"查询钥匙信息",()->controller.keyQuery("钥匙信息",InputRules.identifier(fields.text("uid"),"UID"))));
        keyButtons.add(button(keySection,"读取锁芯协议版本",()->controller.keyQuery("协议版本",InputRules.identifier(fields.text("uid"),"UID"))));
        keyButtons.add(button(keySection,"同步时间（不网络授时）",()->{
            String raw = keyFields.text("time").trim();
            long time = raw.isEmpty() ? System.currentTimeMillis()/1000L : InputRules.seconds(raw,"Unix秒",0,Integer.MAX_VALUE);
            controller.syncTime(keyFields.text("keySecret"),time);
        }));
        authSection = column(); root.addView(authSection);
        text(authSection,"离线授权管理",21);
        controller = new LockController(getApplication(),this);
        authPanel = new OfflineAuthPanel(this,authSection,controller);
        modes.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                permissions.cancel();
                if (controller.initialized() && controller.transport() != selected()) {
                    disableNfc(); controller.close(); fields.clearAll();
                    log("方式改变，已关闭旧会话，请使用内置鉴权重新初始化");
                }
                changed();
            }
            @Override public void onNothingSelected(AdapterView<?> parent) { }
        });
        changed();
    }
    private Transport selected() { return Transport.values()[modes.getSelectedItemPosition()]; }
    private LinearLayout column() { LinearLayout box = new LinearLayout(this); box.setOrientation(LinearLayout.VERTICAL); return box; }
    private TextView text(LinearLayout parent,String value,int size) {
        TextView view = new TextView(this); view.setText(value); view.setTextSize(size); view.setPadding(0,14,0,10); parent.addView(view); return view;
    }
    private Button button(LinearLayout parent,String title,Runnable click) {
        Button b = new Button(this); b.setText(title); parent.addView(b,new LinearLayout.LayoutParams(-1,-2));
        b.setOnClickListener(v->safe(click)); return b;
    }
    private void safe(Runnable action) {
        if (closed) return;
        try { action.run(); }
        catch (RuntimeException | LinkageError error) { log("操作未完成："+Redactor.safe(error.getMessage())); Toast.makeText(this,"请查看本地错误说明",Toast.LENGTH_SHORT).show(); }
    }
    private void confirmLock(boolean open) {
        controller.requireQuery();
        if (!open && !selected().supportsClose()) throw new IllegalArgumentException("BLE仅机械关锁");
        final long session = controller.session();
        final String uid=fields.text("uid"), expected=fields.text("expected"), password=fields.text("pwd"), key=fields.text("lockKey");
        confirmation = new AlertDialog.Builder(this).setTitle(open ? "确认单次开锁" : "确认单次接口关锁")
                .setMessage("当前连接："+controller.deviceLabel()+"\n目标="+expected+"\n请核实设备与实际授权。超时/断线可能结果未知，不自动重发。")
                .setNegativeButton("取消",null).setPositiveButton("确认执行",(dialog,which)->safe(()->{
                    if (!controller.active(session)) throw new IllegalArgumentException("会话已变化，请重新核对目标");
                    controller.operate(open,uid,expected,password,key);
                })).show();
        confirmation.setOnDismissListener(dialog -> confirmation = null);
    }
    private void scan() {
        scanned.clear(); scanLabels.clear();
        scanAdapter = new ArrayAdapter<>(this,android.R.layout.simple_list_item_1,scanLabels);
        scanDialog = new AlertDialog.Builder(this).setTitle("扫描列表：点击选定设备后连接")
                .setAdapter(scanAdapter,(dialog,which)->safe(()->controller.connect(scanned.get(which))))
                .setNegativeButton("停止/取消",null).create();
        scanDialog.setOnDismissListener(dialog->safe(()->controller.stopScan()));
        scanDialog.show(); controller.startScan();
    }
    @Override public void scanned(Device device) {
        if (closed || scanDialog == null || !scanDialog.isShowing() || device == null) return;
        for (Device old : scanned) if (old.getAddress().equals(device.getAddress())) return;
        scanned.add(device); scanLabels.add((device.getName()==null ? "未命名" : device.getName())+"\n"+device.getAddress()); scanAdapter.notifyDataSetChanged();
    }
    private void enableNfc() {
        nfc = NfcAdapter.getDefaultAdapter(this);
        if (nfc == null || !nfc.isEnabled()) { log("请在系统设置启用NFC，再点击重新初始化"); return; }
        final long readSession = controller.session();
        final long generation = ++nfcGeneration;
        nfcEnabled = true;
        nfc.enableReaderMode(this,tag->main.post(()->{
            if (!closed && nfcEnabled && generation == nfcGeneration && controller.active(readSession))
                safe(()->controller.connectTag(tag));
        }), NfcAdapter.FLAG_READER_NFC_A|NfcAdapter.FLAG_READER_NFC_B|NfcAdapter.FLAG_READER_NFC_V|NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK,null);
    }
    private void disableNfc() {
        nfcEnabled = false;
        ++nfcGeneration;
        if (nfc != null) { nfc.disableReaderMode(this); nfc = null; }
    }
    @Override public void changed() {
        if (closed || controller == null || status == null) return;
        status.setText(controller.status());
        boolean busy = controller.busy();
        modes.setEnabled(!busy); initButton.setEnabled(!busy);
        fields.enabled(!busy);
        if (keyFields != null) keyFields.enabled(!busy);
        scanButton.setEnabled(controller.initialized() && !busy && selected().needsBluetooth() && !controller.canQuery());
        for (Button b : queryButtons) b.setEnabled(controller.canQuery());
        countButton.setEnabled(controller.canQuery() && !controller.isKy53E());
        openLockButton.setEnabled(controller.canQuery());
        closeLockButton.setVisibility(selected().supportsClose() ? View.VISIBLE : View.GONE);
        closeLockButton.setEnabled(controller.canQuery() && selected().supportsClose());
        keySection.setVisibility(controller.isKey() ? View.VISIBLE : View.GONE);
        authSection.setVisibility(controller.isKey() ? View.VISIBLE : View.GONE);
        for (Button b : keyButtons) b.setEnabled(controller.canManageAuth());
        if (authPanel != null) authPanel.refresh();
    }
    @Override public void log(String text) {
        if (closed || logView == null) return;
        String time = new java.text.SimpleDateFormat("HH:mm:ss",Locale.ROOT).format(new Date());
        logs.addLast(time+" "+Redactor.safe(text));
        while (logs.size()>200) logs.removeFirst();
        StringBuilder all = new StringBuilder(); for (String line : logs) all.append(line).append('\n');
        boolean followBottom = logScroll != null && !logScroll.canScrollVertically(1);
        logView.setText(all.toString());
        if (followBottom && logScroll != null) logScroll.post(() -> {
            if (!closed) logScroll.fullScroll(View.FOCUS_DOWN);
        });
        changed();
    }
    @Override public void clearLockInputs() {
        if (fields != null) fields.clear("expected","pwd","lockKey");
        if (confirmation != null) confirmation.dismiss();
    }
    @Override public void clearKeyInputs() {
        if (keyFields != null) keyFields.clearAll();
        if (authPanel != null) authPanel.clear();
    }
    @Override protected void onResume() { super.onResume(); main.post(heartbeatRefresh); }
    @Override protected void onPause() {
        main.removeCallbacks(heartbeatRefresh);
        disableNfc();
        // Pausing an NFC page invalidates the session; never leave a "ready" state without reader mode.
        if (controller != null && controller.initialized() && controller.transport() == Transport.NFC) {
            controller.close(); fields.clearAll();
        }
        super.onPause();
    }
    @Override protected void onStop() {
        permissions.cancel();
        if (scanDialog != null) scanDialog.dismiss();
        if (controller != null) controller.close();
        if (fields != null) fields.clearAll();
        super.onStop();
    }
    @Override protected void onDestroy() {
        closed = true; main.removeCallbacksAndMessages(null);
        permissions.cancel();
        if (controller != null) controller.close();
        if (authPanel != null) authPanel.clear();
        super.onDestroy();
    }
    @Override public void onRequestPermissionsResult(int code,String[] names,int[] results) {
        super.onRequestPermissionsResult(code,names,results); permissions.result(code,results);
    }
}
