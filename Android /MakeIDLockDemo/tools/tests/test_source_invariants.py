"""Source-level regression checks only; these do NOT execute Java or validate device behavior."""
from pathlib import Path
import unittest
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
JAVA = ROOT / 'app/src/main/java/com/makeid/makeidlockdemo'

def code(name): return (JAVA/name).read_text()

class SourceInvariants(unittest.TestCase):
    def test_sdk_auth_is_bundled_not_an_input_field(self):
        activity = code('LockDemoActivity.java')
        configuration = code('config/SdkCredentials.java')
        self.assertTrue('com.makeid.makeidlockdemo' in configuration, 'Embedded authorization must bind this package')
        for key in ('APP_ID','APP_SECRET'):
            self.assertTrue(bool(re.search(r'String '+key+r' = "[^"\n]+";',configuration)), 'Missing embedded authorization constant')
        self.assertNotIn('fields.add("appId"', activity)
        self.assertNotIn('fields.add("appSecret"', activity)
        self.assertNotIn('fields.text("appId")', activity)
        controller = code('sdk/LockController.java')
        self.assertIn('SdkCredentials.APP_ID', controller)
        self.assertIn('SdkCredentials.APP_SECRET', controller)
        self.assertIn('SdkCredentials.APPLICATION_ID.equals(app.getPackageName())', controller)
    def test_logs_are_above_independently_scrollable_operations(self):
        root = ET.parse(ROOT/'app/src/main/res/layout/activity_lock_demo.xml').getroot()
        ns = '{http://schemas.android.com/apk/res/android}'
        self.assertEqual('LinearLayout', root.tag)
        self.assertEqual('vertical', root.get(ns+'orientation'))
        ids = [child.get(ns+'id') for child in root]
        self.assertIn('@+id/log_panel', ids)
        self.assertIn('@+id/operation_scroll', ids)
        self.assertLess(ids.index('@+id/log_panel'), ids.index('@+id/operation_scroll'))
        log_panel = next(child for child in root if child.get(ns+'id')=='@+id/log_panel')
        log_ids = [node.get(ns+'id') for node in log_panel.iter()]
        self.assertIn('@+id/log_scroll', log_ids)
        self.assertIn('@+id/log_view', log_ids)
        self.assertIn('@+id/clear_log', log_ids)
        operation = next(child for child in root if child.get(ns+'id')=='@+id/operation_scroll')
        self.assertEqual('ScrollView', operation.tag)
        self.assertEqual('@+id/content', operation[0].get(ns+'id'))
        self.assertIn('canScrollVertically(1)', code('LockDemoActivity.java'))
    def test_nfc_callback_uses_registration_session_and_generation(self):
        source = code('LockDemoActivity.java')
        self.assertIn('final long readSession = controller.session()', source)
        self.assertIn('final long generation = ++nfcGeneration', source)
        self.assertIn('generation == nfcGeneration && controller.active(readSession)', source)
        disabled = source.split('private void disableNfc()', 1)[1].split('@Override', 1)[0]
        self.assertIn('nfcEnabled = false', disabled)
        self.assertIn('++nfcGeneration', disabled)
    def test_nfc_pause_ends_session_not_just_reader_mode(self):
        source = code('LockDemoActivity.java').split('protected void onPause()',1)[1].split('protected void onStop()',1)[0]
        self.assertIn('Transport.NFC', source)
        self.assertIn('controller.close()', source)
        self.assertIn('fields.clearAll()', source)
    def test_reader_target_guard_and_listener_are_both_present(self):
        source = code('sdk/LockController.java')
        self.assertIn('sdk.addReceiveRWSearchCardListener(new MkdLockManagerListener()', source)
        self.assertIn('readerHasCard != present || !readerCardId.equals(next)', source)
        self.assertIn('(!readerHasCard || readerCardId.isEmpty())', source)
        self.assertIn('readerHasCard = false; readerCardId = ""; updateIdentity("")', source)
    def test_auth_stream_error_closes_session(self):
        source = code('sdk/OfflineAuthController.java')
        error = source.split('public void onManageOfflineAuthError',1)[1].split('};',1)[0]
        self.assertIn('host.invalidateUnknown(', error)
        self.assertNotIn('host.finish(', error)
    def test_queried_secrets_are_not_used_for_display_or_input(self):
        source = code('sdk/OfflineAuthController.java')
        summary = source.split('private static String summary',1)[1]
        executable = '\n'.join(line for line in summary.splitlines() if not line.strip().startswith('//'))
        self.assertNotIn('getPassword()', executable)
        self.assertNotIn('getLockSmSecret()', executable)
        self.assertIn('密码=***，锁密钥=***', summary)
    def test_ble_mechanical_close_has_controller_guard(self):
        self.assertIn('return this != BLE', code('core/Transport.java'))
        self.assertIn('!open && !transport.supportsClose()', code('sdk/LockController.java'))
        self.assertIn('View.GONE', code('LockDemoActivity.java'))
    def test_field_storage_and_sdk_dependency_boundaries(self):
        fields = code('ui/ManualFields.java')
        self.assertIn('setSaveEnabled(false)',fields)
        self.assertIn('IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS',fields)
        self.assertNotIn('getSharedPreferences',fields)
        gradle = (ROOT/'app/build.gradle').read_text()
        self.assertIn('verifySdkDelivery',gradle)
        self.assertNotIn('implementation project(',gradle)
    def test_release_blockers_are_not_marked_fixed(self):
        text = (ROOT/'docs/SDK交付阻断.md').read_text()
        self.assertIn('USB绑定未完成时退出',text)
        self.assertIn('NFC公开release未清Tag/监控',text)
        self.assertIn('不是已修复或已真机验证',text)

if __name__ == '__main__': unittest.main()
