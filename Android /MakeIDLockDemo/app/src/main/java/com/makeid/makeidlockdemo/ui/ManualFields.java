package com.makeid.makeidlockdemo.ui;

import android.app.Activity;
import android.os.Build;
import android.text.InputType;
import android.view.View;
import android.widget.*;
import java.util.LinkedHashMap;
import java.util.Map;

/** Manual input only. No preferences, Bundles, Intent payloads, or automatic credential filling. */
public final class ManualFields {
    private final Activity activity;
    private final LinearLayout layout;
    private final Map<String, EditText> fields = new LinkedHashMap<>();
    private final Map<String, CheckBox> reveals = new LinkedHashMap<>();
    public ManualFields(Activity activity, LinearLayout layout) { this.activity = activity; this.layout = layout; }
    public EditText add(String key, String label, boolean secret) {
        TextView title = new TextView(activity); title.setText(label); title.setPadding(0,12,0,2); layout.addView(title);
        EditText edit = new EditText(activity);
        edit.setSingleLine(true); edit.setSaveEnabled(false); edit.setFreezesText(false);
        edit.setInputType(InputType.TYPE_CLASS_TEXT | (secret ? InputType.TYPE_TEXT_VARIATION_PASSWORD : InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS));
        if (Build.VERSION.SDK_INT >= 26) edit.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS);
        layout.addView(edit, new LinearLayout.LayoutParams(-1,-2)); fields.put(key,edit);
        if (secret) {
            CheckBox reveal = new CheckBox(activity); reveal.setText("临时显示此字段"); reveal.setSaveEnabled(false);
            reveal.setOnCheckedChangeListener((button, checked) -> {
                edit.setTransformationMethod(checked ? null : android.text.method.PasswordTransformationMethod.getInstance());
                edit.setSelection(edit.length());
            });
            layout.addView(reveal); reveals.put(key,reveal);
        }
        return edit;
    }
    public String text(String key) { return fields.get(key).getText().toString(); }
    public void clear(String... keys) {
        for (String key : keys) if (fields.containsKey(key)) {
            fields.get(key).setText("");
            if (reveals.containsKey(key)) reveals.get(key).setChecked(false);
        }
    }
    public void clearAll() { clear(fields.keySet().toArray(new String[0])); }
    public void enabled(boolean enabled) {
        for (EditText edit : fields.values()) edit.setEnabled(enabled);
        for (CheckBox reveal : reveals.values()) reveal.setEnabled(enabled);
    }
    public EditText field(String key) { return fields.get(key); }
}
