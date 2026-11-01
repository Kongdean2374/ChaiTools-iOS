#!/usr/bin/env python3
"""Static configuration check. Does not substitute for Swift/Xcode compilation."""
import pathlib
import plistlib
import yaml

root = pathlib.Path(__file__).resolve().parents[1]
project = yaml.safe_load((root / 'project.yml').read_text())
assert set(project['targets']) == {'ChaiTools', 'ChaiToolsKeyboard'}
assert project['targets']['ChaiTools']['dependencies'][0]['embed'] is True
assert project['targets']['ChaiToolsKeyboard']['settings']['base']['APPLICATION_EXTENSION_API_ONLY'] is True
entitlements = []
for name in project['targets']:
    folder = root / name
    info = plistlib.loads((folder / 'Info.plist').read_bytes())
    entitlements.append(plistlib.loads((folder / f'{name}.entitlements').read_bytes()))
    assert info['SharedAppGroup'] == '$(SHARED_APP_GROUP)'
    assert any(folder.glob('*.swift'))
assert entitlements[0] == entitlements[1]
info = plistlib.loads((root / 'ChaiToolsKeyboard/Info.plist').read_bytes())
assert info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.keyboard-service'
assert info['NSExtension']['NSExtensionAttributes']['RequestsOpenAccess'] is True
workflow = yaml.load((root / '.github/workflows/build-unsigned-ipa.yml').read_text(), Loader=yaml.BaseLoader)
assert 'push' in workflow['on'] and 'workflow_dispatch' in workflow['on']
assert 'if-no-files-found' in str(workflow)
for path in root.rglob('*.swift'):
    text = path.read_text()
    assert 'sk-proj-' not in text and 'sk-live-' not in text
print('PASS: configuration, embedded extension, shared entitlements, workflow triggers, source credential scan')

import json
import struct
version = (root/'VERSION').read_text().strip()
assert project['settings']['base']['MARKETING_VERSION'] == version
assert project['targets']['ChaiTools']['settings']['base']['ASSETCATALOG_COMPILER_APPICON_NAME'] == 'AppIcon'
icon = root/'ChaiTools/Assets.xcassets/AppIcon.appiconset'
manifest = json.loads((icon/'Contents.json').read_text())
data = (icon/manifest['images'][0]['filename']).read_bytes()
assert data[:8] == b'\x89PNG\r\n\x1a\n'
width, height, depth, color = struct.unpack('>IIBB', data[16:26])
assert (width, height, depth, color) == (1024, 1024, 8, 2), 'Icon must be opaque RGB 1024px'
for path in (root/'ChaiTools/Assets.xcassets').rglob('Contents.json'):
    json.loads(path.read_text())
print('PASS: version consistency, app icon configuration, opaque 1024px icon, asset manifests')

source = '\n'.join(p.read_text() for p in root.rglob('*.swift'))
for forbidden in ['SecItemAdd(', 'SecItemUpdate(', 'SecItemCopyMatching(', 'Keychain.load(', 'Keychain.save(']:
    assert forbidden not in source, forbidden
assert source.count('SecItemDelete(') == 1, 'Only scoped delete-only legacy cleanup is allowed'
store = (root/'Shared/CredentialStore.swift').read_text()
for required in ['.completeFileProtection', '.isExcludedFromBackup = true', '.posixPermissions: 0o600', '.posixPermissions: 0o700', '.atomic']:
    assert required in store
client = (root/'Shared/AIClient.swift').read_text()
assert client.index('CredentialPayloadGuard.validate(body, key: key)') < client.index('request("responses", key: key, body: body)')
assert not (root/'Shared/Keychain.swift').exists()
print('PASS: protected credential file configuration, no Keychain reads/writes, payload guard before network')

routing = (root/'Shared/StorageLocation.swift').read_text()
assert 'applicationSupportDirectory' in routing
assert 'guard !isExtension else' in routing
assert 'StorageLocation.current().url' in (root/'Shared/CredentialStore.swift').read_text()
assert 'StorageLocation.current().url' in (root/'Shared/Storage.swift').read_text()
assert 'cleanupError' not in (root/'ChaiTools/ChaiToolsApp.swift').read_text()
assert 'try LegacyCredentialCleanup.runOnce()' not in source
print('PASS: shared routing for key/preferences/history, host local fallback, extension isolation, nonblocking legacy cleanup')
