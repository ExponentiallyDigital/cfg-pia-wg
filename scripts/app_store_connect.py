#!/usr/bin/env python3
"""App Store Connect, driven from the repo through its API, so nobody types the listing in by hand.

  python scripts/app_store_connect.py listing [--check]   the listing, screenshots, age rating, review notes (ID-455)
  python scripts/app_store_connect.py testers             an internal TestFlight group with Andrew in it (ID-465)
  python scripts/app_store_connect.py whats-new --build N --notes FILE   a build's TestFlight notes (ID-432)

--check reads and checks every file and says what it would send, and sends nothing; it needs no key.
Otherwise the key comes from the environment, as release.yml's iOS job has it (ID-463):
APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID and APP_STORE_CONNECT_API_KEY (the .p8 text).

What the API can't do stays by hand: the App Privacy answers, and attaching the demo video.
Needs PyJWT with cryptography, and requests, at the versions the workflows pin.
"""
import argparse
import hashlib
import os
import re
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_STORE = os.path.join(ROOT, 'app-store')
BUNDLE_ID = 'com.exponentiallydigital.cfgpiawg'
LOCALE = 'en-AU'
BASE = 'https://api.appstoreconnect.apple.com'

# App Store Connect's own ids for the categories listing.md names.
CATEGORIES = {'Utilities': 'UTILITIES', 'Productivity': 'PRODUCTIVITY'}

# Screenshot folders and the display slot each one fills (scripts/app-store-screenshots.py).
SCREENSHOT_SETS = [('iphone', 'APP_IPHONE_67'), ('ipad', 'APP_IPAD_PRO_3GEN_129')]

# Version states whose metadata can still be changed.
EDITABLE = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY'}

# The age rating questions (privacy_and_age_rating.md: every one None or No, so 4+). Only those the
# API returns are sent, so a question Apple adds or drops can't fail the run.
AGE_NONE = [
    'alcoholTobaccoOrDrugUseOrReferences', 'contests', 'gamblingSimulated', 'gunsOrOtherWeapons',
    'horrorOrFearThemes', 'matureOrSuggestiveThemes', 'medicalOrTreatmentInformation',
    'profanityOrCrudeHumor', 'sexualContentGraphicAndNudity', 'sexualContentOrNudity',
    'violenceCartoonOrFantasy', 'violenceRealistic', 'violenceRealisticProlongedGraphicOrSadistic',
]
AGE_NO = [
    'advertising', 'ageAssurance', 'gambling', 'healthOrWellnessTopics', 'lootBox', 'messagingAndChat',
    'parentalControls', 'unrestrictedWebAccess', 'userGeneratedContent',
]


def die(message):
    print(f'::error::{message}')
    sys.exit(1)


# ── The files ──────────────────────────────────────────────────────────────────────────────

def read(name):
    with open(os.path.join(APP_STORE, name), encoding='utf-8') as f:
        return f.read()


def listing_fields(text):
    """listing.md's values: the first line under each `## Heading (limit)`, keyed by the heading."""
    fields = {}
    for m in re.finditer(r'^## ([^\n(]+?)\s*(?:\([^)]*\))?\n\n([^\n]+)', text, re.M):
        fields[m.group(1).strip()] = m.group(2).strip()
    return fields


def review_notes(text):
    """review_notes.md below its first `---` line: the text App Review reads, as it is."""
    parts = re.split(r'^---\s*$', text, maxsplit=1, flags=re.M)
    if len(parts) != 2:
        die('app-store/review_notes.md has no --- line above the notes')
    return parts[1].strip()


def gather():
    fields = listing_fields(read('listing.md'))
    need = ['Name', 'Subtitle', 'Promotional text', 'Keywords', 'Primary category', 'Secondary category',
            'Support URL', 'Marketing URL', 'Privacy policy URL', 'Copyright']
    missing = [n for n in need if n not in fields]
    if missing:
        die(f'app-store/listing.md is missing {", ".join(missing)}')
    for n in ('Primary category', 'Secondary category'):
        if fields[n] not in CATEGORIES:
            die(f'{n} "{fields[n]}" is not one of {", ".join(CATEGORIES)}')
    plan = {
        'fields': fields,
        'description': read('description.md').strip(),
        'notes': review_notes(read('review_notes.md')),
        'screenshots': {},
    }
    if '[VIDEO LINK]' in plan['notes']:
        die('app-store/review_notes.md still has the [VIDEO LINK] placeholder')
    for folder, slot in SCREENSHOT_SETS:
        d = os.path.join(APP_STORE, 'screenshots', folder)
        files = sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith('.png')) if os.path.isdir(d) else []
        if not files:
            die(f'no screenshots in app-store/screenshots/{folder}: run scripts/app-store-screenshots.py')
        plan['screenshots'][slot] = files
    return plan


def show(plan):
    f = plan['fields']
    for n in ('Name', 'Subtitle', 'Promotional text', 'Keywords', 'Primary category', 'Secondary category',
              'Support URL', 'Marketing URL', 'Privacy policy URL', 'Copyright'):
        print(f'  {n}: {f[n]}')
    print(f'  Description: {len(plan["description"])} characters')
    print(f'  Review notes: {len(plan["notes"])} characters')
    for slot, files in plan['screenshots'].items():
        print(f'  {slot}: {len(files)} screenshots')


# ── The API ────────────────────────────────────────────────────────────────────────────────

class Api:
    def __init__(self):
        import jwt  # PyJWT
        import requests
        self._jwt, self._http = jwt, requests
        self.key_id = os.environ.get('APP_STORE_CONNECT_KEY_ID', '')
        self.issuer = os.environ.get('APP_STORE_CONNECT_ISSUER_ID', '')
        self.key = os.environ.get('APP_STORE_CONNECT_API_KEY', '')
        missing = [n for n, v in (('APP_STORE_CONNECT_KEY_ID', self.key_id), ('APP_STORE_CONNECT_ISSUER_ID', self.issuer),
                                  ('APP_STORE_CONNECT_API_KEY', self.key)) if not v]
        if missing:
            die(f'these are empty: {", ".join(missing)} (ID-463)')

    def _token(self):
        now = int(time.time())
        claims = {'iss': self.issuer, 'iat': now, 'exp': now + 1100, 'aud': 'appstoreconnect-v1'}
        return self._jwt.encode(claims, self.key, algorithm='ES256', headers={'kid': self.key_id, 'typ': 'JWT'})

    def call(self, method, path, body=None, params=None):
        url = path if path.startswith('http') else BASE + path
        r = self._http.request(method, url, json=body, params=params, timeout=60,
                               headers={'Authorization': f'Bearer {self._token()}'})
        if r.status_code >= 400:
            die(f'{method} {path}: HTTP {r.status_code} {r.text[:1500]}')
        return r.json() if r.content else {}

    def get(self, path, **params):
        return self.call('GET', path, params=params or None)

    def patch(self, kind, id_, attributes=None, relationships=None):
        data = {'type': kind, 'id': id_}
        if attributes:
            data['attributes'] = attributes
        if relationships:
            data['relationships'] = relationships
        return self.call('PATCH', f'/v1/{kind}/{id_}', {'data': data})

    def post(self, kind, attributes, relationships):
        return self.call('POST', f'/v1/{kind}', {'data': {'type': kind, 'attributes': attributes,
                                                          'relationships': relationships}})['data']


def rel(kind, id_):
    return {'data': {'type': kind, 'id': id_}}


def app_id(api):
    apps = api.get('/v1/apps', **{'filter[bundleId]': BUNDLE_ID})['data']
    if not apps:
        die(f'no App Store Connect app for {BUNDLE_ID} (ID-427)')
    return apps[0]['id']


def editable_app_info(api, app):
    infos = api.get(f'/v1/apps/{app}/appInfos')['data']
    done = {'READY_FOR_DISTRIBUTION', 'READY_FOR_SALE', 'REPLACED_WITH_NEW_INFO'}
    for info in infos:
        state = info['attributes'].get('state') or info['attributes'].get('appStoreState')
        if state not in done:
            return info['id']
    return infos[0]['id']


def editable_version(api, app, version_string):
    versions = api.get(f'/v1/apps/{app}/appStoreVersions', **{'filter[platform]': 'IOS'})['data']
    for v in versions:
        a = v['attributes']
        if (a.get('appVersionState') or a.get('appStoreState')) in EDITABLE:
            return v['id']
    print(f'  no editable version: creating {version_string}')
    return api.post('appStoreVersions', {'platform': 'IOS', 'versionString': version_string},
                    {'app': rel('apps', app)})['id']


def localization(api, path, kind, parent_kind, parent_id, create):
    """The en-AU localization under [path], made with [create]'s attributes when there isn't one."""
    for loc in api.get(path)['data']:
        if loc['attributes'].get('locale') == LOCALE:
            return loc['id']
    return api.post(kind, {'locale': LOCALE, **create}, {parent_kind: rel(parent_kind + 's', parent_id)})['id']


def pubspec_version():
    with open(os.path.join(ROOT, 'pubspec.yaml'), encoding='utf-8') as f:
        m = re.search(r'^version:\s*([0-9.]+)\+(\d+)', f.read(), re.M)
    if not m:
        die('no version in pubspec.yaml')
    return m.group(1), m.group(2)


def upload_screenshots(api, version_loc, slot, files):
    sets = api.get(f'/v1/appStoreVersionLocalizations/{version_loc}/appScreenshotSets')['data']
    found = [s for s in sets if s['attributes'].get('screenshotDisplayType') == slot]
    if found:
        set_id = found[0]['id']
        for old in api.get(f'/v1/appScreenshotSets/{set_id}/appScreenshots')['data']:
            api.call('DELETE', f'/v1/appScreenshots/{old["id"]}')
    else:
        set_id = api.post('appScreenshotSets', {'screenshotDisplayType': slot},
                          {'appStoreVersionLocalization': rel('appStoreVersionLocalizations', version_loc)})['id']
    for path in files:
        with open(path, 'rb') as f:
            data = f.read()
        shot = api.post('appScreenshots', {'fileName': os.path.basename(path), 'fileSize': len(data)},
                        {'appScreenshotSet': rel('appScreenshotSets', set_id)})
        for op in shot['attributes']['uploadOperations']:
            chunk = data[op['offset']:op['offset'] + op['length']]
            headers = {h['name']: h['value'] for h in op.get('requestHeaders', [])}
            r = api._http.request(op['method'], op['url'], data=chunk, headers=headers, timeout=120)
            if r.status_code >= 400:
                die(f'uploading {path}: HTTP {r.status_code} {r.text[:500]}')
        api.patch('appScreenshots', shot['id'], {'uploaded': True, 'sourceFileChecksum': hashlib.md5(data).hexdigest()})
        print(f'  {slot}: {os.path.basename(path)} uploaded')


def cmd_listing(args):
    plan = gather()
    show(plan)
    if args.check:
        print('::notice::Check only: every file reads, and nothing was sent to App Store Connect.')
        return
    api = Api()
    f = plan['fields']
    app = app_id(api)
    version_string, _ = pubspec_version()

    info = editable_app_info(api, app)
    loc = localization(api, f'/v1/appInfos/{info}/appInfoLocalizations', 'appInfoLocalizations', 'appInfo', info,
                       {'name': f['Name']})
    api.patch('appInfoLocalizations', loc, {'name': f['Name'], 'subtitle': f['Subtitle'],
                                            'privacyPolicyUrl': f['Privacy policy URL']})
    api.patch('appInfos', info, relationships={
        'primaryCategory': rel('appCategories', CATEGORIES[f['Primary category']]),
        'secondaryCategory': rel('appCategories', CATEGORIES[f['Secondary category']]),
    })
    print('  name, subtitle, privacy policy URL and categories set')

    age = api.get(f'/v1/appInfos/{info}/ageRatingDeclaration')['data']
    present = age.get('attributes', {})
    answers = {k: 'NONE' for k in AGE_NONE if k in present}
    answers.update({k: False for k in AGE_NO if k in present})
    api.patch('ageRatingDeclarations', age['id'], answers)
    print(f'  age rating: {len(answers)} questions answered None or No')

    version = editable_version(api, app, version_string)
    api.patch('appStoreVersions', version, {'copyright': f['Copyright']})
    vloc = localization(api, f'/v1/appStoreVersions/{version}/appStoreVersionLocalizations',
                        'appStoreVersionLocalizations', 'appStoreVersion', version, {})
    api.patch('appStoreVersionLocalizations', vloc, {
        'description': plan['description'], 'keywords': f['Keywords'], 'promotionalText': f['Promotional text'],
        'supportUrl': f['Support URL'], 'marketingUrl': f['Marketing URL'],
    })
    print('  description, keywords, promotional text and URLs set')

    review = {'notes': plan['notes'], 'demoAccountRequired': False}
    for key, env in (('contactFirstName', 'APP_REVIEW_FIRST_NAME'), ('contactLastName', 'APP_REVIEW_LAST_NAME'),
                     ('contactEmail', 'APP_REVIEW_EMAIL'), ('contactPhone', 'APP_REVIEW_PHONE')):
        if os.environ.get(env):
            review[key] = os.environ[env]
    existing = api.get(f'/v1/appStoreVersions/{version}/appStoreReviewDetail').get('data')
    if existing:
        api.patch('appStoreReviewDetails', existing['id'], review)
    else:
        api.post('appStoreReviewDetails', review, {'appStoreVersion': rel('appStoreVersions', version)})
    print(f'  review notes set{"" if "contactPhone" in review else "; no APP_REVIEW_PHONE, so the contact phone is left as it is"}')

    for slot, files in plan['screenshots'].items():
        upload_screenshots(api, vloc, slot, files)
    print('::notice::The listing is in App Store Connect. Left by hand: App Privacy, and the demo video.')


def cmd_testers(args):
    api = Api()
    app = app_id(api)
    email = os.environ.get('TESTFLIGHT_TESTER_EMAIL', '')
    if not email:
        die('TESTFLIGHT_TESTER_EMAIL is empty')
    groups = [g for g in api.get(f'/v1/apps/{app}/betaGroups')['data'] if g['attributes'].get('isInternalGroup')]
    if groups:
        group = groups[0]['id']
    else:
        group = api.post('betaGroups', {'name': 'Internal', 'isInternalGroup': True, 'hasAccessToAllBuilds': True},
                         {'app': rel('apps', app)})['id']
        print('  internal group "Internal" made, with every build')
    in_group = api.get(f'/v1/betaGroups/{group}/betaTesters')['data']
    if any(t['attributes'].get('email', '').lower() == email.lower() for t in in_group):
        print(f'  {email} is already a tester')
        return
    known = api.get('/v1/betaTesters', **{'filter[email]': email})['data']
    if known:
        api.call('POST', f'/v1/betaGroups/{group}/relationships/betaTesters',
                 {'data': [{'type': 'betaTesters', 'id': known[0]['id']}]})
    else:
        api.post('betaTesters', {'email': email, 'firstName': os.environ.get('APP_REVIEW_FIRST_NAME', ''),
                                 'lastName': os.environ.get('APP_REVIEW_LAST_NAME', '')},
                 {'betaGroups': {'data': [{'type': 'betaGroups', 'id': group}]}})
    print(f'  {email} added to the internal group')


def cmd_whats_new(args):
    with open(args.notes, encoding='utf-8') as f:
        notes = f.read().strip()
    if not notes:
        die(f'{args.notes} is empty')
    api = Api()
    app = app_id(api)
    # Apple takes some minutes to process an upload before the build can carry notes.
    build = None
    for _ in range(40):
        found = api.get('/v1/builds', **{'filter[app]': app, 'filter[version]': args.build})['data']
        if found and found[0]['attributes'].get('processingState') == 'VALID':
            build = found[0]
            break
        state = found[0]['attributes'].get('processingState') if found else 'not there yet'
        print(f'  build {args.build}: {state}; waiting')
        time.sleep(60)
    if not build:
        die(f'build {args.build} did not finish processing in 40 minutes')
    a = build['attributes']
    # ID-430: Info.plist answers the encryption question, so a processed build carries the answer.
    print(f'  build {args.build}: usesNonExemptEncryption = {a.get("usesNonExemptEncryption")}')
    loc = None
    for l in api.get(f'/v1/builds/{build["id"]}/betaBuildLocalizations')['data']:
        if l['attributes'].get('locale') == LOCALE:
            loc = l['id']
    if loc:
        api.patch('betaBuildLocalizations', loc, {'whatsNew': notes})
    else:
        api.post('betaBuildLocalizations', {'locale': LOCALE, 'whatsNew': notes}, {'build': rel('builds', build['id'])})
    print(f'  build {args.build}: TestFlight notes set ({len(notes)} characters)')


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)
    l = sub.add_parser('listing')
    l.add_argument('--check', action='store_true')
    sub.add_parser('testers')
    w = sub.add_parser('whats-new')
    w.add_argument('--build', required=True)
    w.add_argument('--notes', required=True)
    args = p.parse_args()
    {'listing': cmd_listing, 'testers': cmd_testers, 'whats-new': cmd_whats_new}[args.cmd](args)


if __name__ == '__main__':
    main()
