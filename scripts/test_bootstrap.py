import pathlib
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch
import bootstrap

class BootstrapTests(unittest.TestCase):
    def test_permissions_and_plist_are_idempotent(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            manifest = root / 'android/app/src/main/AndroidManifest.xml'
            manifest.parent.mkdir(parents=True)
            manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="app"/></manifest>')
            gradle = root / 'android/app/build.gradle.kts'
            gradle.write_text('minSdk = flutter.minSdkVersion')
            info = root / 'ios/Runner/Info.plist'
            info.parent.mkdir(parents=True)
            info.write_bytes(plistlib.dumps({'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)'}))
            with patch.object(bootstrap, 'ROOT', root), patch.object(bootstrap.shutil, 'which', return_value='/flutter'), patch.object(bootstrap.subprocess, 'run'):
                bootstrap.main()
                bootstrap.main()
            tree = ET.parse(manifest).getroot()
            names = [p.get(bootstrap.attr('name')) for p in tree.findall('uses-permission')]
            self.assertEqual(len(names), len(set(names)))
            self.assertIn('android.permission.FOREGROUND_SERVICE_LOCATION', names)
            self.assertEqual(gradle.read_text(), 'minSdk = 23')
            data = plistlib.loads(info.read_bytes())
            self.assertEqual(data['UIBackgroundModes'], ['location'])
            self.assertIn('NSLocalNetworkUsageDescription', data)
            self.assertEqual(data['CFBundleIdentifier'], '$(PRODUCT_BUNDLE_IDENTIFIER)')

if __name__ == '__main__':
    unittest.main()
