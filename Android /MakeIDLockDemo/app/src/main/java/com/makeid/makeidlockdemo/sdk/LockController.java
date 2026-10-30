package com.makeid.makeidlockdemo.sdk;

import android.app.Application;
import android.hardware.usb.UsbManager;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.nfc.Tag;

import com.makeid.blelibrary.bean.Device;
import com.makeid.lock_2.MkdLockManagerNewer;
import com.makeid.lock_2.ble.listener.MkdBleConnectListener;
import com.makeid.lock_2.ble.listener.MkdScanListener;
import com.makeid.lock_2.constant.MkdLockTypeEnum;
import com.makeid.lock_2.entity.MkdLockResult;
import com.makeid.lock_2.listener.MkdLockManagerListener;
import com.makeid.lock_2.listener.MkdLockManagerProgressListener;
import com.makeid.lock_2.lock.usb.MkdUsbIndependentServer;
import com.makeid.mkdelectronickeylib.entity.*;
import com.makeid.mkdelectronickeylib.listener.*;
import com.makeid.makeidlockdemo.core.*;
import com.makeid.makeidlockdemo.config.SdkCredentials;

import java.util.Map;
import java.util.Locale;

/** One Activity owns one SDK session. No HTTP, credential lookup, direct Helper, or auto-unlock. */
public final class LockController {
    public interface View {
        void changed();
        void log(String text);
        void clearLockInputs();
        void clearKeyInputs();
        void scanned(Device device);
    }
    public interface Work { void send(long token); }
    private final Application app;
    private final View view;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final MkdLockManagerNewer sdk = MkdLockManagerNewer.getInstance();
    private final OperationGate gate = new OperationGate();
    private long session;
    private boolean initialized;
    private boolean connected;
    private boolean usbReady;
    private boolean broken;
    private Transport transport = Transport.NFC;
    private String name = "";
    private String deviceAddress = "";
    private String identity = "";
    private String tagId = "";
    private String readerCardId = "";
    private boolean readerHasCard;
    private HeartEntity heart;
    private long heartAt;
    private long connectToken;
    private Runnable deadline;
    public LockController(Application app, View view) { this.app = app; this.view = view; }
    public MkdLockManagerNewer sdk() { return sdk; }
    public long session() { return session; }
    public boolean active(long value) { return initialized && session == value && !broken; }
    public boolean initialized() { return initialized; }
    public boolean busy() { return gate.isBusy(); }
    public Transport transport() { return transport; }
    public boolean isKey() { return transport == Transport.READER && (isKy53E() || name.toUpperCase(Locale.ROOT).startsWith("KY53N")); }
    public boolean isKy53E() { return name.toUpperCase(Locale.ROOT).startsWith("KY53E"); }
    public boolean canQuery() { return initialized && connected && !broken && !busy(); }
    public boolean canManageAuth() { return canQuery() && isKey() && freshHeart(); }
    public String identity() { return identity; }
    public String deviceLabel() { return name + (deviceAddress.isEmpty() ? "" : " / " + deviceAddress); }
    public boolean freshHeart() { return heart != null && SystemClock.elapsedRealtime() - heartAt < 15000; }
    public String status() {
        if (!initialized) return "未初始化（切换模式/返回后台后需重新初始化，设备密码与密钥仍需手工输入）";
        return transport.label + " · " + (broken ? "需重新建立会话" : busy() ? "操作中" : connected ? "已连接" : "等待设备")
                + "\n设备：" + (name.isEmpty() ? "—" : deviceLabel()) + "\n目标身份：" + (identity.isEmpty() ? "未识别，请先查询" : identity)
                + (isKey() && heart != null ? "\n锁芯连接=" + heart.getLockCylinderState() + "，锁状态=" + heart.getLockState()
                    + "，钥匙模式=" + heart.getElectronicKeyEncryptMode() + "，锁模式=" + heart.getLockEncryptMode()
                    + "，钥匙电量=" + heart.getElectronicKeyBattery() : "");
    }
    public void initialize(Transport selected) {
        close();
        transport = selected;
        if (!SdkCredentials.APPLICATION_ID.equals(app.getPackageName()))
            throw new IllegalArgumentException("当前应用包名与内置SDK授权不匹配，不能初始化");
        if (selected == Transport.USB) {
            UsbManager usb = (UsbManager) app.getSystemService(Application.USB_SERVICE);
            if (!app.getPackageManager().hasSystemFeature("android.hardware.usb.host") || usb == null)
                throw new IllegalArgumentException("设备不支持USB host/OTG");
            if (usb.getDeviceList().size() > 1) throw new IllegalArgumentException("仅支持单台USB锁/适配器，请移除其他USB外设");
        }
        try {
            if (!sdk.initWithAppID(SdkCredentials.APP_ID, SdkCredentials.APP_SECRET, app))
                throw new IllegalArgumentException("本地鉴权失败：检查凭证是否绑定 com.makeid.makeidlockdemo");
            initialized = true;
            final long current = session;
            if (selected == Transport.USB) registerUsb(current);
            sdk.changeCurrentLockType(selected == Transport.NFC ? MkdLockTypeEnum.MKD_LOCK_TYPE_NFC
                    : selected == Transport.BLE ? MkdLockTypeEnum.MKD_LOCK_TYPE_BLE
                    : selected == Transport.USB ? MkdLockTypeEnum.MKD_LOCK_TYPE_USB : MkdLockTypeEnum.MKD_LOCK_TYPE_READER);
            if (selected == Transport.READER) {
                sdk.addReceiveRWSearchCardListener(new MkdLockManagerListener() {
                    @Override public void onFailed(MkdLockResult error) {
                        main.post(() -> {
                            if (!active(current) || !connected || isKy53E()) return;
                            readerHasCard = false; readerCardId = ""; updateIdentity(""); view.clearLockInputs();
                            if (busy()) invalidateUnknown("操作期间读写器寻卡失败");
                            else { view.log("读写器寻卡失败，目标与实时凭证已失效：" + failure(error)); view.changed(); }
                        });
                    }
                    @Override public void onSuccess(Map<String, String> card) {
                        main.post(() -> {
                            if (!active(current) || !connected || isKy53E() || card == null) return;
                            boolean present = "1".equals(card.get("hasCard"));
                            String next = present && card.get("uid") != null ? card.get("uid") : "";
                            boolean changed = readerHasCard != present || !readerCardId.equals(next);
                            readerHasCard = present; readerCardId = next;
                            if (changed) {
                                updateIdentity("");
                                view.clearLockInputs();
                                if (busy()) { invalidateUnknown("操作期间读写器目标变化/移开"); return; }
                                view.log(present ? "读写器发现目标，请手工重新查询并核对SN" : "读写器目标已移开，实时凭证已清除");
                            }
                            view.changed();
                        });
                    }
                });
                sdk.setOnElectronicKeyHeartBeatListener(new OnHeartBeatListener() {
                    @Override public void onHeartBeat(HeartEntity value) {
                        main.post(() -> {
                            if (!active(current) || !connected || value == null) return;
                            String next = value.getLockCylinderState() == 1 ? value.getLockSN() : "";
                            boolean changed = heart != null && !identity.equals(next == null ? "" : next);
                            heart = value;
                            heartAt = SystemClock.elapsedRealtime();
                            updateIdentity(next);
                            // Hot-swapping a cylinder while an A3 request is pending is unsafe.
                            if (changed && busy()) { invalidateUnknown("操作期间锁芯身份变化"); return; }
                            view.changed();
                        });
                    }
                    @Override public void onHeartBeatFail(int code, String error) {
                        main.post(() -> { if (active(current)) view.log("心跳失败 " + code); });
                    }
                });
            }
            view.log("本地初始化完成；不会自动获取密钥或开锁");
            if (selected == Transport.USB) {
                connectToken = begin("等待USB授权与数据通道", 45000, token -> { });
                if (sdk.isUsbConnected()) usbState(current, true);
            }
            view.changed();
        } catch (RuntimeException | LinkageError error) {
            close();
            throw new IllegalArgumentException("初始化失败：" + Redactor.safe(error.getMessage()));
        }
    }
    private void registerUsb(long current) {
        sdk.setUSBRunningListener(new MkdUsbIndependentServer.IUsbConnectListener() {
            @Override public void onUsbConnect() {
                main.post(() -> {
                    if (!active(current)) return;
                    UsbManager usb = (UsbManager) app.getSystemService(Application.USB_SERVICE);
                    if (usb != null && usb.getDeviceList().size() > 1) { invalidateUnknown("检测到多个USB外设，已终止会话"); return; }
                    view.log("USB物理接入，不代表数据就绪");
                });
            }
            @Override public void onUsbDisConnect() { main.post(() -> { if (active(current)) invalidateUnknown("USB拔出"); }); }
            @Override public void onUsbDataConnectStatus(boolean status) { main.post(() -> usbState(current, status)); }
        });
    }
    private void usbState(long current, boolean ready) {
        if (!active(current)) return;
        if (!ready) {
            if (usbReady) invalidateUnknown("USB数据通道断开");
            return;
        }
        UsbManager usb = (UsbManager) app.getSystemService(Application.USB_SERVICE);
        if (usb == null || usb.getDeviceList().size() != 1) { invalidateUnknown("USB设备不明确，请仅接入一台受支持设备"); return; }
        android.hardware.usb.UsbDevice peripheral = usb.getDeviceList().values().iterator().next();
        usbReady = true; connected = true;
        name = "USB VID=" + peripheral.getVendorId() + " PID=" + peripheral.getProductId() + " " + peripheral.getDeviceName();
        finish(connectToken, "USB数据通道已连接，请手动查询并核对锁身份", true);
        view.changed();
    }
    public void startScan() {
        requireInitialized();
        if (!transport.needsBluetooth() || busy() || connected) throw new IllegalArgumentException("请先断开旧连接，再扫描");
        final long current = session;
        sdk.setDeviceScanPrefix(transport == Transport.READER ? new String[]{"KY53E", "KY53N", "YS"} : new String[]{"LOCK-"});
        sdk.startScan(15000, new MkdScanListener() {
            @Override public void onScanStart() { main.post(() -> { if (active(current)) view.log("扫描开始，用户选择后才连接"); }); }
            @Override public void onScanStop() { main.post(() -> { if (active(current)) view.log("扫描结束"); }); }
            @Override public void onScanResult(Device value, boolean systemConnected) {
                main.post(() -> { if (active(current) && !busy() && !connected) view.scanned(value); });
            }
            @Override public void onScanError(String error) { main.post(() -> { if (active(current)) view.log("扫描失败：" + Redactor.safe(error)); }); }
        });
    }
    public void stopScan() { if (initialized) { sdk.stopScan(); sdk.removeScanListener(); } }
    public void connect(Device value) {
        requireInitialized();
        if (busy() || connected) throw new IllegalArgumentException("请先断开旧连接");
        stopScan();
        final long current = session;
        name = value.getName() == null ? "" : value.getName();
        deviceAddress = value.getAddress();
        view.clearKeyInputs();
        connectToken = begin("连接设备", 40000, token -> sdk.connectDevice(value, new MkdBleConnectListener() {
            @Override public void connectSuccess(Device device) {
                main.post(() -> {
                    if (!active(current)) return;
                    connected = true;
                    finish(token, "已连接，请等待钥匙心跳或读写器寻卡后手工查询", true);
                });
            }
            @Override public void connectFailed(String error) { main.post(() -> { if (active(current)) invalidateUnknown("连接失败：" + Redactor.safe(error)); }); }
            @Override public void connectClose() { main.post(() -> { if (active(current)) invalidateUnknown("BLE断开"); }); }
        }));
    }
    public void connectTag(Tag tag) {
        if (!initialized || transport != Transport.NFC || broken) return;
        StringBuilder hex = new StringBuilder();
        for (byte v : tag.getId()) hex.append(String.format(Locale.ROOT, "%02X", v & 255));
        String nextTag = hex.toString();
        if (connected && tagId.equals(nextTag)) return;
        if (busy()) { invalidateUnknown("NFC Tag变化或连接期间重复靠卡，请重建会话"); return; }
        tagId = nextTag;
        updateIdentity("");
        final long current = session;
        begin("连接NFC Tag", 15000, token -> sdk.connectTag(tag, status -> main.post(() -> {
            if (!active(current)) return;
            if (!status) { invalidateUnknown("NFC连接失败/Tag丢失"); return; }
            connected = true; name = "手机NFC";
            finish(token, "Tag已连接，请手动读取基础信息", true);
        })));
    }
    private void requireInitialized() { if (!initialized || broken) throw new IllegalArgumentException("请先本地初始化并重建会话"); }
    public void requireQuery() { requireInitialized(); if (!connected || busy()) throw new IllegalArgumentException("未连接或正在执行上一操作"); }
    public void requireKey() {
        requireQuery();
        if (!isKey() || !freshHeart()) throw new IllegalArgumentException("请连接KY53E/KY53N并等待15秒内的有效心跳");
        int mode = heart.getElectronicKeyEncryptMode();
        if (mode != 1 && mode != 2) throw new IllegalArgumentException("钥匙侧加密模式未知，不能执行加密业务");
    }
    public long begin(String operation, long timeoutMs, Work work) {
        requireInitialized();
        long token = gate.begin();
        final long current = session;
        view.log(operation + "（单次手动调用）");
        deadline = () -> { if (active(current) && gate.isCurrent(token)) invalidateUnknown(operation + "等待超时，结果未知；不自动重发"); };
        main.postDelayed(deadline, timeoutMs);
        view.changed();
        try { work.send(token); }
        catch (RuntimeException | LinkageError error) { if (active(current)) invalidateUnknown(operation + "异常：" + Redactor.safe(error.getMessage())); }
        return token;
    }
    public boolean current(long currentSession, long token) { return active(currentSession) && gate.isCurrent(token); }
    public void finish(long token, String message, boolean success) {
        if (!gate.finish(token)) return;
        if (deadline != null) main.removeCallbacks(deadline);
        deadline = null;
        view.log((success ? "完成：" : "失败：") + Redactor.safe(message));
        view.changed();
    }
    public void accept(long currentSession, long token, String message, boolean ok) {
        main.post(() -> { if (current(currentSession, token)) finish(token, message, ok); });
    }
    public void progress(long currentSession, long token, String text) {
        main.post(() -> { if (current(currentSession, token)) view.log(Redactor.safe(text)); });
    }
    public void invalidateUnknown(String reason) {
        view.log(Redactor.safe(reason) + "；会话已终止，请核实设备后重新初始化");
        close();
    }
    public void close() {
        boolean hadSession = initialized;
        ++session; initialized = false; connected = false; usbReady = false; broken = false;
        gate.invalidate();
        readerHasCard = false; readerCardId = "";
        if (deadline != null) main.removeCallbacks(deadline);
        deadline = null; connectToken = 0; heart = null; heartAt = 0; name = ""; deviceAddress = ""; identity = ""; tagId = "";
        view.clearLockInputs(); view.clearKeyInputs();
        if (hadSession) {
            try { sdk.stopScan(); sdk.removeScanListener(); sdk.setOnElectronicKeyHeartBeatListener(null); sdk.addReceiveRWSearchCardListener(null); sdk.setElectronicKeySmSecret(null); sdk.unRegisMkdLockReportListener(); sdk.release(); }
            catch (RuntimeException | LinkageError error) { view.log("清理异常，重新打开页面前核实外设状态：" + Redactor.safe(error.getMessage())); }
        }
        view.changed();
    }
    private void updateIdentity(String next) {
        next = next == null ? "" : next;
        if (!identity.equals(next)) { identity = next; view.clearLockInputs(); }
    }
    public void query(String action, String manualUid) {
        requireQuery();
        String uid = isKey() ? InputRules.identifier(manualUid, "UID") : "";
        if (isKey() && !freshHeart()) throw new IllegalArgumentException("请等待有效心跳");
        if (isKy53E()) {
            if ("开锁次数".equals(action)) throw new IllegalArgumentException("KY53E不支持通用开锁次数查询");
            keyQuery(action, uid); return;
        }
        final long current = session;
        begin(action, 45000, token -> {
            MkdLockManagerListener listener = new MkdLockManagerListener() {
                @Override public void onFailed(MkdLockResult result) { fail(current, token, result); }
                @Override public void onSuccess(Map<String,String> data) {
                    main.post(() -> {
                        if (!current(current, token)) return;
                        if ("基础信息".equals(action) && data != null) updateIdentity(data.get("sn"));
                        StringBuilder out = new StringBuilder(action);
                        // Allowlist display keys; never dump arbitrary maps/password fields.
                        for (String key : new String[]{"sn","mac","lockStatus","nfcElectricity","batteryElectricity","solarEnergyElectricity","version","hardwareVersion","unlockTimes","communicationEncryptionMode"})
                            if (data != null && data.containsKey(key)) out.append("\n").append(key).append('=').append(data.get(key));
                        finish(token, out.toString(), true);
                    });
                }
            };
            if ("基础信息".equals(action)) sdk.readLockBasicInfoSuccess(listener);
            else if ("状态电量".equals(action)) sdk.readStatusAndElectricity(listener);
            else if ("版本".equals(action)) sdk.readFWVersion(listener);
            else sdk.readUnlockTimes(listener);
        });
    }
    public void keyQuery(String action, String uid) {
        requireKey();
        final long current = session;
        begin(action, 30000, token -> {
            if ("基础信息".equals(action)) sdk.readElectronicKeyLockSN(uid, new OnReadSerialNoListener() {
                @Override public void onReadLockSN(LockInfo info) { accept(current, token, "锁芯SN=" + (info == null ? "无" : info.getSerialNo()), info != null); }
                @Override public void onReadLockSNError(int code, String error) { accept(current, token, "读SN失败 " + code + ":" + error, false); }
            });
            else if ("状态电量".equals(action)) sdk.readElectronicKeyLockState(uid, new OnReadLockStateListener() {
                @Override public void onReadLockState(LockStateEntity info) { accept(current, token, info == null ? "无状态" : "锁状态=" + info.getLockStaDatSet() + ", NFC电压=" + info.getNfcVolt() + ", 系统电压=" + info.getSystemVoltageMv(), info != null); }
                @Override public void onReadLockStateError(int code, String error) { accept(current, token, "读状态失败 " + code + ":" + error, false); }
            });
            else if ("版本".equals(action)) sdk.readElectronicKeyLockFirmwareVersion(new OnReadLockFirmwareVersionListener() {
                @Override public void onReadLockFirmwareVersion(LockFirmwareVersionInfo info) { accept(current, token, info == null ? "无版本" : "固件=" + info.getFirmwareVersion() + ", 硬件=" + info.getHardwareVersion(), info != null); }
                @Override public void onReadLockFirmwareVersionError(int code, String error) { accept(current, token, "固件版本失败 " + code + ":" + error, false); }
            });
            else if ("协议版本".equals(action)) sdk.readElectronicKeyLockProtocolVersion(new OnReadLockProtocolVersionListener() {
                @Override public void onReadLockProtocolVersion(LockProtocolVersionInfo info) { accept(current, token, info == null ? "无协议" : "协议=" + info.getMainVersion() + "." + info.getSubVersion() + ", 类型=" + info.getType(), info != null); }
                @Override public void onReadLockProtocolVersionError(int code, String error) { accept(current, token, "协议版本失败 " + code + ":" + error, false); }
            });
            else sdk.readElectronicKeyInfo(uid, new OnReadElectKeyInfoListener() {
                @Override public void onReadElectKeyInfo(ElectronicKeyInfo info) { accept(current, token, info == null ? "无钥匙信息" : "钥匙=" + info.getDname() + ", 版本=" + info.getDhfversion() + ", 授权条数=" + info.getAuthsize(), info != null); }
                @Override public void onReadElectKeyInfoError(int code, String error) { accept(current, token, "钥匙信息失败 " + code + ":" + error, false); }
            });
        });
    }
    public void syncTime(String keySecret, long seconds) {
        requireKey();
        String key = InputRules.secret(keySecret, "钥匙侧密钥");
        final long current = session;
        begin("同步手机Unix秒", 30000, token -> {
            sdk.setElectronicKeySmSecret(key);
            sdk.syncElectronicKeyTime(seconds, new OnSyncTimeListener() {
                @Override public void onSyncTime(boolean success, long timestamp) { accept(current, token, "时间同步结果=" + success, success); }
                @Override public void onSyncTimeError(int code, String error) { accept(current, token, "时间同步失败 " + code + ":" + error, false); }
            });
        });
    }
    public void operate(boolean open, String uidText, String expected, String passwordText, String lockKeyText) {
        requireQuery();
        if (!open && !transport.supportsClose()) throw new IllegalArgumentException("直连BLE锁使用机械结构关锁，无接口关锁");
        if (transport == Transport.READER && !isKy53E() && (!readerHasCard || readerCardId.isEmpty()))
            throw new IllegalArgumentException("请等待读写器寻卡确认目标，移开/换卡后需重新查询SN");
        if (identity.isEmpty() || !identity.equals(InputRules.required(expected, "预期目标SN"))) throw new IllegalArgumentException("先读取身份，并手工填写匹配的预期目标SN");
        if (isKey() && (!freshHeart() || heart.getLockCylinderState() != 1)) throw new IllegalArgumentException("钥匙锁芯未连接或心跳过期");
        String password = InputRules.hex(passwordText, "锁密码", isKy53E() ? 4 : 1, isKy53E() ? 4 : 16, false);
        String lockKey = InputRules.hex(lockKeyText, "锁侧密钥", 16, 16, !isKy53E());
        if (isKy53E() && heart.getLockEncryptMode() != 1 && heart.getLockEncryptMode() != 2) throw new IllegalArgumentException("锁侧加密模式未知");
        String uid = isKy53E() ? InputRules.identifier(uidText, "UID") : "";
        final long current = session;
        begin(open ? "手动开锁" : "手动关锁", 60000, token -> {
            MkdLockManagerProgressListener listener = new MkdLockManagerProgressListener() {
                @Override public void onChargeProgress(int percent) { progress(current, token, "进度=" + percent + "%（不是最终成功）"); }
                @Override public void onFailed(MkdLockResult result) { fail(current, token, result); }
                @Override public void onSuccess(Map<String,String> result) { accept(current, token, "设备操作返回成功，请核实实际状态", true); }
            };
            if (isKy53E()) {
                if (open) sdk.unlockElectronicKeyWithSecretKey(uid, password, lockKey, listener);
                else sdk.lockElectronicKeyWithSecretKey(uid, password, lockKey, listener);
            } else {
                String key = transport == Transport.BLE || transport == Transport.USB || lockKey.isEmpty() ? null : lockKey;
                if (open) sdk.unlockWithSecretKey(password, key, listener);
                else sdk.lockWithSecretKey(password, key, listener);
            }
        });
    }
    private void fail(long currentSession, long token, MkdLockResult result) {
        main.post(() -> {
            if (!current(currentSession, token)) return;
            if (result == MkdLockResult.TAG_LOST || result == MkdLockResult.BLENoConnect
                    || result == MkdLockResult.DEV_UN_LINK || result == MkdLockResult.ConnectFail
                    || result == MkdLockResult.RecResponseNull) {
                invalidateUnknown(failure(result));
            } else finish(token, failure(result), false);
        });
    }
    private static String failure(MkdLockResult result) { return result == null ? "未知失败" : result.name() + " / " + result.getKey() + " / " + result.getValue(); }
}
