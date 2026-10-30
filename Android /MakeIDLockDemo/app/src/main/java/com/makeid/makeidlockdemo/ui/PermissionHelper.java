package com.makeid.makeidlockdemo.ui;

import android.Manifest;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.os.Build;
import android.widget.Toast;
import com.makeid.makeidlockdemo.core.Transport;

public final class PermissionHelper {
    public static final int REQUEST = 3101;
    private final Activity activity;
    private Runnable pending;
    public PermissionHelper(Activity activity) { this.activity = activity; }
    private String[] permissions() {
        return Build.VERSION.SDK_INT >= 31 ? new String[]{Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT}
                : new String[]{Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION};
    }
    public void run(Transport mode, Runnable action) {
        if (!mode.needsBluetooth()) { action.run(); return; }
        pending = action;
        if (Build.VERSION.SDK_INT >= 23) for (String permission : permissions()) {
            if (activity.checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
                activity.requestPermissions(permissions(), REQUEST); return;
            }
        }
        proceed();
    }
    public void result(int code, int[] results) {
        if (code != REQUEST || pending == null) return;
        if (results.length == 0) { pending = null; return; }
        for (int result : results) if (result != PackageManager.PERMISSION_GRANTED) {
            pending = null; toast("权限未授予，可在系统设置处理后重试"); return;
        }
        proceed();
    }
    private void proceed() {
        Runnable action = pending; pending = null;
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null || !adapter.isEnabled()) { toast("请先在系统设置打开蓝牙"); return; }
        if (Build.VERSION.SDK_INT < 31) {
            LocationManager location = (LocationManager) activity.getSystemService(Activity.LOCATION_SERVICE);
            boolean enabled = location != null && (location.isProviderEnabled(LocationManager.GPS_PROVIDER) || location.isProviderEnabled(LocationManager.NETWORK_PROVIDER));
            if (!enabled) { toast("Android 6～11扫描还需系统定位服务开启"); return; }
        }
        if (action != null) action.run();
    }
    public void cancel() { pending = null; }
    private void toast(String text) { Toast.makeText(activity,text,Toast.LENGTH_LONG).show(); }
}
