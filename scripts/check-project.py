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
