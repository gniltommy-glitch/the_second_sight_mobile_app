#!/usr/bin/env python3
"""Generate SDK-owned native projects, then apply SecondSight permissions.
Works on macOS/Linux/Windows with Python 3 and Flutter on PATH.
Does not overwrite application code. Idempotent after native generation.
"""
import pathlib
import plistlib
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
ANDROID = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', ANDROID)
def attr(name):
    return '{' + ANDROID + '}' + name

def main():
    flutter = shutil.which('flutter')
    if not flutter:
        raise SystemExit('Install Flutter stable, add flutter/bin to PATH, then run again.')
    if not (ROOT / 'android').exists() or not (ROOT / 'ios').exists():
        with tempfile.TemporaryDirectory(prefix='secondsight-native-') as temp:
            target = pathlib.Path(temp) / 'secondsight'
            subprocess.run([flutter, 'create', '--platforms=android,ios', '--org', 'vn.secondsight',
                '--project-name', 'secondsight', '--no-pub', str(target)], check=True)
            for platform in ('android', 'ios'):
                if not (ROOT / platform).exists():
                    shutil.copytree(target / platform, ROOT / platform)
            if (target / '.metadata').exists():
                shutil.copy2(target / '.metadata', ROOT / '.metadata')
    manifest = ROOT / 'android/app/src/main/AndroidManifest.xml'
    tree = ET.parse(manifest)
    root = tree.getroot()
    permissions = ['INTERNET', 'ACCESS_NETWORK_STATE', 'ACCESS_WIFI_STATE',
        'ACCESS_FINE_LOCATION', 'ACCESS_COARSE_LOCATION', 'FOREGROUND_SERVICE',
        'FOREGROUND_SERVICE_LOCATION', 'RECORD_AUDIO', 'VIBRATE', 'WAKE_LOCK']
    existing = {p.get(attr('name')) for p in root.findall('uses-permission')}
    for p in permissions:
        p = 'android.permission.' + p
        if p not in existing:
            ET.SubElement(root, 'uses-permission', {attr('name'): p})
    app = root.find('application')
    app.set(attr('label'), 'SecondSight')
    # Runtime PiLink also blocks HTTP unless user enables LAN test mode.
    app.set(attr('usesCleartextTraffic'), 'true')
    app.set(attr('allowBackup'), 'false')
    queries = root.find('queries')
    if queries is None:
        queries = ET.SubElement(root, 'queries')
    if not queries.findall("intent/action[@" + attr('name') + "='android.speech.RecognitionService']"):
        intent = ET.SubElement(queries, 'intent')
        ET.SubElement(intent, 'action', {attr('name'): 'android.speech.RecognitionService'})
    for scheme in ('tel', 'https'):
        exists = any(d.get(attr('scheme')) == scheme for d in queries.findall('intent/data'))
        if not exists:
            intent = ET.SubElement(queries, 'intent')
            ET.SubElement(intent, 'action', {attr('name'): 'android.intent.action.VIEW'})
            ET.SubElement(intent, 'data', {attr('scheme'): scheme})
    ET.indent(tree, space='    ')
    tree.write(manifest, encoding='utf-8', xml_declaration=True)
    for name in ('build.gradle.kts', 'build.gradle'):
        gradle = ROOT / 'android/app' / name
        if gradle.exists():
            text = gradle.read_text()
            text = re.sub(r'minSdk\s*=\s*flutter.minSdkVersion', 'minSdk = 23', text)
            text = text.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 23')
            gradle.write_text(text)
    info = ROOT / 'ios/Runner/Info.plist'
    with info.open('rb') as f:
        plist = plistlib.load(f)
    plist.update({
        'CFBundleDisplayName': 'SecondSight',
        'NSLocationWhenInUseUsageDescription': 'SecondSight dùng GPS điện thoại để chỉ đường đi bộ.',
        'NSLocationAlwaysAndWhenInUseUsageDescription': 'Tiếp tục GPS trong hành trình khi màn hình khóa.',
        'NSMicrophoneUsageDescription': 'Nhập điểm đến bằng giọng nói khi bạn nhấn micro.',
        'NSSpeechRecognitionUsageDescription': 'Chuyển lời nói thành địa chỉ tìm kiếm.',
        'NSLocalNetworkUsageDescription': 'Kết nối kính SecondSight trên mạng hotspot hoặc Wi-Fi của bạn.',
        'NSBonjourServices': ['_secondsight._tcp', '_http._tcp'],
        'UIBackgroundModes': ['location'],
        'LSApplicationQueriesSchemes': ['tel', 'https'],
        'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True},
    })
    with info.open('wb') as f:
        plistlib.dump(plist, f, sort_keys=False)
    subprocess.run([flutter, 'pub', 'get'], cwd=ROOT, check=True)
    print('Native Android/iOS projects configured. Next: flutter analyze && flutter test && flutter run')

if __name__ == '__main__':
    main()
