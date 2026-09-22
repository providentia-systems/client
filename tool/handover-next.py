#!/usr/bin/env python3
"""Keep existing regression coverage and pair the backend catalog contract."""
from pathlib import Path
import gzip
import hashlib
import json
import subprocess

p = Path('test/core/synchronization/generated_sync_gateway_test.dart')
s = p.read_text()
s = s.replace('operation status HTTP $statusCode is authorization failure', 'unclassified operation status HTTP $statusCode preserves saved intent')
a = s.index("'unclassified operation status HTTP $statusCode")
b = s.index("'operation status rejects malformed", a)
s = s[:a] + s[a:b].replace('isA<AuthorizationSyncException>()', 'isA<RetryableSyncException>()') + s[b:]
s = s.replace('HTTP $statusCode blocks each pushed operation as authorization failure', 'unclassified HTTP $statusCode blocks uploads without proving home revocation')
a = s.index("'unclassified HTTP $statusCode blocks uploads")
b = s.index("  for (final method in <String>['bootstrap', 'pull'])", a)
part = s[a:b].replace('PushResultKind.authorizationFailure', 'PushResultKind.validationError')
part = part.replace("          'Home access is unavailable.',", "          contains('saved work has been kept'),")
part = part.replace('        final response = await', '        final response = await', 1)
part = part.replace('        expect(\n          response.results.single.safeMessage,', "        expect(response.results.single.code, 'unclassified_http_denial');\n        expect(\n          response.results.single.safeMessage,")
s = s[:a] + part + s[b:]
a = s.index("  for (final method in <String>['bootstrap', 'pull'])")
b = s.index("  test('pull maps the exact HTTP 410", a)
part = s[a:b].replace('$method HTTP $statusCode is authorization, not authentication', '$method verified HTTP $statusCode home denial is authorization, not authentication')
part = part.replace("'type': 'about:blank',", "'type': 'https://providentia.invalid/problems/sync_home_access_denied',")
part = part.replace("contains('membership')", "contains('home')")
s = s[:a] + part + s[b:]
p.write_text(s)
p = Path('test/core/synchronization/session_bound_sync_gateway_test.dart')
s = p.read_text()
a = s.index("'legacy installation-bound intent")
b = s.index("  test('an account change", a)
s = s[:a] + s[a:b].replace('isA<AuthenticationSyncException>()', "isA<BindingSyncException>().having((error) => error.code, 'code', 'device_binding_mismatch')") + s[b:]
p.write_text(s)
p = Path('test/core/synchronization/sync_coordinator_test.dart')
s = p.read_text()
a = s.index("'a blocked command remains a durable barrier")
b = s.index("'bootstrap membership loss", a)
s = s[:a] + s[a:b].replace('SyncRunStatus.completed', 'SyncRunStatus.uploadsBlocked') + s[b:]
s = s.replace('operation status HTTP $statusCode is a purge-class authorization outcome', 'verified home denial from operation status HTTP $statusCode is an authorization outcome')
p.write_text(s)

archive = Path('contracts/source/providentia-v1.json.gz')
old_zip = archive.read_bytes()
old_json = gzip.decompress(old_zip)
contract = json.loads(old_json)
parameters = contract['paths']['/api/v1/catalog-admin/entities/{entityType}']['get'].setdefault('parameters', [])
if not any(p.get('name') == 'q' and p.get('in') == 'query' for p in parameters):
    parameters.append({'name': 'q', 'in': 'query', 'required': False,
        'description': 'Literal, case-insensitive identity search applied before offset pagination. Empty text lists all authorized records.',
        'schema': {'type': 'string', 'maxLength': 191, 'default': ''}})
    new_json = (json.dumps(contract, ensure_ascii=False, indent=2) + '\n').encode()
    new_zip = gzip.compress(new_json, mtime=0)
    archive.write_bytes(new_zip)
    replacements = {hashlib.sha256(old_json).hexdigest(): hashlib.sha256(new_json).hexdigest(),
                    hashlib.sha256(old_zip).hexdigest(): hashlib.sha256(new_zip).hexdigest()}
    for filename in subprocess.check_output(['git', 'ls-files'], text=True).splitlines():
        p = Path(filename)
        if not p.is_file() or p == archive or 'handover-next.py' in filename:
            continue
        try:
            data = p.read_bytes()
            text = data.decode()
        except (UnicodeError, OSError):
            continue
        if data == old_json:
            p.write_bytes(new_json)
            continue
        updated = text
        for before, after in replacements.items():
            updated = updated.replace(before, after)
        if updated != text:
            p.write_text(updated)
            print('Updated contract digest pin:', filename)
    print('Paired contract hashes:', json.dumps(replacements))
print('Explicit-denial and blocked-upload regression expectations updated; paired contract retained.')
