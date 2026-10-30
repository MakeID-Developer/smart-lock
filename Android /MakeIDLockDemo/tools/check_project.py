#!/usr/bin/env python3
"""Non-compiling source/Manifest checks. Does not execute Gradle, javac, or SDK calls."""
from pathlib import Path
import re, sys, xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parents[1]
JAVA = ROOT / 'app/src/main/java/com/makeid/makeidlockdemo'
REQUIRED = ['MainActivity.java', 'LockDemoActivity.java', 'core/InputRules.java',
            'core/Transport.java', 'core/OperationGate.java', 'core/Redactor.java',
            'sdk/LockController.java', 'sdk/OfflineAuthController.java',
            'ui/OfflineAuthPanel.java', 'ui/ManualFields.java', 'ui/PermissionHelper.java']
def check():
    problems = []
    for file in REQUIRED:
        if not (JAVA / file).is_file(): problems.append('Missing implementation: ' + file)
    ns = '{http://schemas.android.com/apk/res/android}'
    tools = '{http://schemas.android.com/tools}'
    manifest = ET.parse(ROOT / 'app/src/main/AndroidManifest.xml').getroot()
    if manifest.find('application').get(ns+'allowBackup') != 'false': problems.append('Backups must be disabled')
    for permission in manifest.findall('uses-permission'):
        if permission.get(ns+'name') == 'android.permission.INTERNET' and permission.get(tools+'node') != 'remove':
            problems.append('Runtime INTERNET permission enabled')
    for file in JAVA.rglob('*.java'):
        source = file.read_text()
        for pattern in [r'import\s+(?:okhttp3|retrofit2|java\.net|com\.tencent\.bugly)\.',
                        r'com\.makeid\.AndroidIoTTestTool', r'MkdElectronicKeyManager',
                        r'MkdFiberClearLib|MkdXCFiberCheckLib', r'MkdNetHelper|HttpUtil',
                        r'readAXLockPassword\s*\(']:
            if re.search(pattern, source): problems.append(f'{file.name}: prohibited path {pattern}')
    # Enforce manual inputs and mechanical BLE closing at both UI and controller boundaries.
    for file in JAVA.rglob('*.java'):
        source = file.read_text()
        clean = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
        if re.search(r'getSharedPreferences|PreferenceManager|putExtra\s*\(|putString\s*\(', clean):
            problems.append(file.name + ': credential/session persistence path')
    lock = JAVA / 'sdk/LockController.java'
    if lock.is_file():
        code = lock.read_text()
        if '!open && !transport.supportsClose()' not in code:
            problems.append('Controller must reject interface closing for mechanical BLE locks')
        if 'onHeartBeat' in code:
            callback = code.split('onHeartBeat(HeartEntity', 1)[1].split('onHeartBeatFail', 1)[0]
            if re.search(r'\.operate\(|unlock\w*\(|sendElectronicKeyOfflineAuth\(', callback):
                problems.append('Heartbeat must not initiate writes')
    transport = JAVA / 'core/Transport.java'
    if transport.is_file() and 'return this != BLE' not in transport.read_text():
        problems.append('BLE close capability must remain mechanical-only')
    auth = JAVA / 'sdk/OfflineAuthController.java'
    if auth.is_file():
        clean = re.sub(r'/\*.*?\*/|//[^\n]*', '', auth.read_text(), flags=re.S)
        if re.search(r'getPassword\s*\(|getLockSmSecret\s*\(', clean):
            problems.append('Do not read returned auth secrets into display/input')
        for name in ['sendElectronicKeyOfflineAuth','queryElectronicKeyOfflineAuth',
                     'queryAllElectronicKeyOfflineAuth','deleteElectronicKeyOfflineAuth',
                     'deleteAllElectronicKeyOfflineAuth']:
            if name not in clean: problems.append('Missing offline authorization operation: '+name)
    for path in (ROOT / 'app/src/main/res').rglob('*.xml'):
        try: ET.parse(path)
        except ET.ParseError as error: problems.append(str(path.relative_to(ROOT))+': '+str(error))
    for path in JAVA.rglob('*.java'):
        if any(line.rstrip() != line for line in path.read_text().splitlines()):
            problems.append(path.name+': trailing whitespace')
    build = (ROOT/'app/build.gradle').read_text()
    if 'implementation project(' in build: problems.append('Must use local AARs, not repository modules')
    if problems:
        for message in problems: print('FAIL:', message)
        return 1
    print('PASS: independent files, no network/old app/device libraries, no credential reads, disabled backups')
    try:
        import javalang
    except ImportError:
        print('NOTE: optional Java grammar parser not installed; run with tools/requirements-static.txt for grammar checking.')
    else:
        count = 0
        for path in (ROOT/'app/src').rglob('*.java'):
            try: javalang.parse.parse(path.read_text())
            except javalang.parser.JavaSyntaxError as error:
                print('FAIL: Java syntax', path.relative_to(ROOT), error.description, error.at)
                return 1
            count += 1
        print('PASS: Java source grammar parsed (not type-checked or compiled):', count)
    print('PASS: all five offline operations, no auth-secret display reads, mechanical BLE close guard, XML resources')
    print('Static checks only; not compilation, functional tests, or physical-device validation.')
    return 0
if __name__ == '__main__': sys.exit(check())
