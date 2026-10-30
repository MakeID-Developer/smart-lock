#!/usr/bin/env python3
"""Read-only local AAR inventory; does not package or build anything."""
from pathlib import Path
import hashlib, sys, zipfile, json
ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {'MkdLockLib.aar': '1.7.19', 'MkdElectronicKeyLib.aar': '1.0.2', 'makeid_bleconnectlib_1.1.aar': '1.1'}
def main():
    missing = []
    records = []
    for filename, expected_version in EXPECTED.items():
        path = ROOT / 'app/libs' / filename
        if not path.is_file():
            missing.append(filename); print('MISSING:', filename); continue
        try:
            with zipfile.ZipFile(path) as archive:
                names = archive.namelist()
                if 'AndroidManifest.xml' not in names or 'classes.jar' not in names:
                    raise ValueError('Not a complete AAR')
                abis = sorted({n.split('/')[1] for n in names if n.startswith('jni/') and n.endswith('.so')})
                records.append({'file':filename, 'expected_version':expected_version,
                                'actual_version':'requires supplier confirmation',
                                'sha256':hashlib.sha256(path.read_bytes()).hexdigest(), 'abis':abis})
        except (zipfile.BadZipFile, ValueError) as error:
            missing.append(filename); print('INVALID:',filename,str(error))
    print(json.dumps(records, indent=2, ensure_ascii=False))
    if missing:
        print('BLOCKED: supplier AAR delivery incomplete. No build or packaging was attempted.')
        return 1
    print('AAR inventory present; contents, matching versions, shared OpenSSL and physical-device compatibility still require review.')
    return 0
if __name__ == '__main__': sys.exit(main())
