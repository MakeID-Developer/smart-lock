package com.makeid.makeidlockdemo;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.widget.*;
import com.makeid.makeidlockdemo.databinding.ActivityMainBinding;

/** Deliberately local: no Application initializer, login, remote configuration, or telemetry. */
public final class MainActivity extends Activity {
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        ActivityMainBinding binding = ActivityMainBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());
        LinearLayout page = binding.content;
        TextView title = new TextView(this); title.setText("MakeID\n智能锁 · 电子钥匙"); title.setTextSize(30); title.setTextColor(0xff126b62); page.addView(title);
        TextView body = new TextView(this); body.setTextSize(16); body.setPadding(0,32,0,24);
        body.setText("离线 SDK 参考 Demo\n\n• 手机NFC、BLE读写器/KY钥匙、直连BLE锁、USB\n• 密码与两侧密钥均由操作者手工输入\n• 钥匙离线授权：下发、查单、查全、删单、删全\n• 直连BLE锁通过机械结构关锁，无接口关锁\n\n不提供登录、网络请求、自动获取密码、仪表入口。设备操作须具有实际授权。\n\nSDK：MkdLockLib 1.7.19 / MkdElectronicKeyLib 1.0.2 / BLE 1.1\n授权包名："+getPackageName()+"\n\n源码未经过编译或真机验证。请先放入供应方配套AAR，核对ABI及SDK敏感日志，再在受控设备上验证。AAR使用者无需原SDK源码。");
        page.addView(body);
        Button start = new Button(this); start.setText("进入智能锁 / 电子钥匙"); page.addView(start);
        start.setOnClickListener(v -> startActivity(new Intent(this,LockDemoActivity.class)));
    }
}
