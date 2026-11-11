"""Synthetic package fixtures test validation, never produce a runnable iPhone app."""
import importlib.util
import plistlib
import struct
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('ipa_validator', Path(__file__).parents[1] / 'validate-ipa.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

def executable(platform=2, cpu=validator.ARM64):
    command = struct.pack('<6I', 0x32, 24, platform, 0x110000, 0x120000, 0)
    return struct.pack('<8I', 0xFEEDFACF, cpu, 0, 2, 1, len(command), 0, 0) + command

class IPAValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'synthetic-fixture.zip'

    def fixture(self, binary=None, platform='iPhoneOS', executable_mode=0o100755, extra=None, live=False):
        info = {'CFBundleExecutable':'WHOOP', 'CFBundlePackageType':'APPL',
                'CFBundleDisplayName':'WHOOP', 'CFBundleIdentifier':'test.fixture',
                'CFBundleSupportedPlatforms':[platform], 'NSSupportsLiveActivities':live}
        with zipfile.ZipFile(self.path, 'w') as archive:
            archive.writestr('Payload/WHOOP.app/Info.plist', plistlib.dumps(info))
            entry = zipfile.ZipInfo('Payload/WHOOP.app/WHOOP')
            entry.external_attr = executable_mode << 16
            archive.writestr(entry, executable() if binary is None else binary)
            if extra: extra(archive)
        return self.path

    def test_arm64_ios_structure_accepted_without_claiming_signature(self):
        result = validator.validate(self.fixture())
        self.assertEqual(result['platform'], 'iOS device')
        self.assertEqual(result['signing'], 'not checked')

    def test_arm64_simulator_load_command_is_rejected_even_if_plist_says_iphone(self):
        with self.assertRaisesRegex(ValueError, 'simulator'):
            validator.validate(self.fixture(binary=executable(platform=7)))

    def test_simulator_info_is_rejected_even_if_executable_says_iphone(self):
        with self.assertRaisesRegex(ValueError, 'iPhoneOS'):
            validator.validate(self.fixture(platform='iPhoneSimulator'))

    def test_x86_64_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'arm64'):
            validator.validate(self.fixture(binary=executable(cpu=0x01000007)))

    def test_nonexecutable_permission_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'permission'):
            validator.validate(self.fixture(executable_mode=0o100644))

    def test_missing_platform_and_truncated_load_commands_are_rejected(self):
        cases = [struct.pack('<8I', 0xFEEDFACF, validator.ARM64, 0, 2, 0, 0, 0, 0),
                 executable()[:-1], b'not a mach-o executable']
        for binary in cases:
            with self.subTest(binary=binary), self.assertRaises(ValueError):
                validator.validate(self.fixture(binary=binary))

    def test_other_apple_platforms_are_rejected(self):
        for platform in (1, 3, 4, 6, 11):
            with self.subTest(platform=platform), self.assertRaises(ValueError):
                validator.validate(self.fixture(binary=executable(platform=platform)))

    def test_unsafe_zip_path_and_duplicate_entries_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            validator.validate(self.fixture(extra=lambda z:z.writestr('../outside', 'bad')))
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            path = self.fixture(extra=lambda z:z.writestr('Payload/WHOOP.app/WHOOP', executable()))
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            validator.validate(path)

    def extension(self, archive, platform=2):
        info={'CFBundlePackageType':'XPC!','CFBundleSupportedPlatforms':['iPhoneOS'],
              'CFBundleIdentifier':'test.fixture.WorkoutLive','CFBundleExecutable':'WorkoutLive'}
        archive.writestr('Payload/WHOOP.app/PlugIns/WorkoutLive.appex/Info.plist',plistlib.dumps(info))
        entry=zipfile.ZipInfo('Payload/WHOOP.app/PlugIns/WorkoutLive.appex/WorkoutLive')
        entry.external_attr=0o100755 << 16
        archive.writestr(entry,executable(platform=platform))

    def test_declared_live_activities_require_an_embedded_extension(self):
        with self.assertRaisesRegex(ValueError,'widget extension'):
            validator.validate(self.fixture(live=True))

    def test_device_widget_is_validated_and_listed(self):
        result=validator.validate(self.fixture(live=True,extra=self.extension))
        self.assertEqual(result['embedded_extensions'],['WorkoutLive.appex'])

    def test_simulator_widget_is_rejected_even_with_a_device_main_binary(self):
        with self.assertRaisesRegex(ValueError,'simulator'):
            validator.validate(self.fixture(live=True,extra=lambda z:self.extension(z,platform=7)))

    def test_multiple_main_apps_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'exactly one'):
            validator.validate(self.fixture(extra=lambda z:z.writestr('Payload/Other.app/file', 'bad')))

if __name__ == '__main__':
    unittest.main()
