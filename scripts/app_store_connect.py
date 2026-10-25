#!/usr/bin/env python3
"""App Store Connect, driven from the repo through its API, so nobody types the listing in by hand.

  python scripts/app_store_connect.py listing [--check]   the listing, screenshots, age rating, review notes (ID-455)
  python scripts/app_store_connect.py testers             an internal TestFlight group with Andrew in it (ID-465)
  python scripts/app_store_connect.py whats-new --build N --notes FILE   a build's TestFlight notes (ID-432)
  python scripts/app_store_connect.py attach-build --build N   the build the App Store version is submitted with (ID-436)
  python scripts/app_store_connect.py has-build --build N      whether Apple already has that build number (ID-468)
  python scripts/app_store_connect.py promote --build N --to alpha|beta|production [--dry-run]   Play's tracks, on the App Store (ID-468)
  python scripts/app_store_connect.py note-certificates --to FILE        the team's certificates before a CI archive (ID-469)
  python scripts/app_store_connect.py revoke-new-certificates --since FILE   the Development ones the run made, revoked (ID-469)

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
    if not os.path.isfile(IAP_SCREENSHOT):
        die('no app-store/screenshots/iap-review.png: run test/release/paywall_screenshot_test.dart (its header says how)')
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
    print(f'  {IAP_PRODUCT}: review screenshot {os.path.basename(IAP_SCREENSHOT)}')


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
        data = {'type': kind, 'relationships': relationships}
        if attributes:
            data['attributes'] = attributes
        return self.call('POST', f'/v1/{kind}', {'data': data})['data']


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

    # privacy_and_age_rating.md, Content rights: Andrew's answer, 2026-10-21.
    api.patch('apps', app, {'contentRightsDeclaration': 'DOES_NOT_USE_THIRD_PARTY_CONTENT'})
    print('  content rights: no third-party content')

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
    # The version number is pubspec.yaml's, as on Play, and as the build it is submitted with carries:
    # App Store Connect made the record at 1.0 (2026-10-21).
    api.patch('appStoreVersions', version, {'copyright': f['Copyright'], 'versionString': version_string})
    print(f'  version {version_string}, copyright {f["Copyright"]}')
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
        print(f'  review notes set{"" if "contactPhone" in review else "; no APP_REVIEW_PHONE, so the contact phone is left as it is"}')
    elif 'contactPhone' in review:
        api.post('appStoreReviewDetails', review, {'appStoreVersion': rel('appStoreVersions', version)})
        print('  review notes and contact set')
    else:
        # Apple won't make the review details without a phone, in the form +61 4xx xxx xxx (2026-10-20).
        print('::warning::No APP_REVIEW_PHONE secret, so the review notes and contact were not set. Add it, '
              'with the country code (+61 ...), and run this again.')

    for slot, files in plan['screenshots'].items():
        upload_screenshots(api, vloc, slot, files)
    upload_iap_screenshot(api, app)
    print('::notice::The listing is in App Store Connect. Left by hand: App Privacy, and the demo video.')


IAP_PRODUCT = 'lifetime_unlock'
IAP_SCREENSHOT = os.path.join(APP_STORE, 'screenshots', 'iap-review.png')


def upload(api, path, kind, relationship, rel_kind, parent_id):
    """One file through App Store Connect's upload operations, for [kind] (a screenshot of some sort)."""
    with open(path, 'rb') as f:
        data = f.read()
    item = api.post(kind, {'fileName': os.path.basename(path), 'fileSize': len(data)},
                    {relationship: rel(rel_kind, parent_id)})
    for op in item['attributes']['uploadOperations']:
        chunk = data[op['offset']:op['offset'] + op['length']]
        headers = {h['name']: h['value'] for h in op.get('requestHeaders', [])}
        r = api._http.request(op['method'], op['url'], data=chunk, headers=headers, timeout=120)
        if r.status_code >= 400:
            die(f'uploading {path}: HTTP {r.status_code} {r.text[:500]}')
    api.patch(kind, item['id'], {'uploaded': True, 'sourceFileChecksum': hashlib.md5(data).hexdigest()})


def upload_iap_screenshot(api, app):
    """The paywall, drawn by test/release/paywall_screenshot_test.dart, as the in-app purchase's
    review screenshot (ID-454), replacing any already there."""
    found = api.get(f'/v1/apps/{app}/inAppPurchasesV2', **{'filter[productId]': IAP_PRODUCT})['data']
    if not found:
        die(f'no in-app purchase {IAP_PRODUCT} (ID-464)')
    iap = found[0]['id']
    old = api.get(f'/v2/inAppPurchases/{iap}/appStoreReviewScreenshot').get('data')
    if old:
        api.call('DELETE', f'/v1/inAppPurchaseAppStoreReviewScreenshots/{old["id"]}')
    upload(api, IAP_SCREENSHOT, 'inAppPurchaseAppStoreReviewScreenshots', 'inAppPurchaseV2', 'inAppPurchases', iap)
    print(f'  {IAP_PRODUCT}: review screenshot uploaded')


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


def cmd_attach_build(args):
    """The processed build [args.build] becomes the one the App Store version is submitted with (ID-436).
    Apple takes only a build whose version number is the version's, so a mismatch stops here."""
    api = Api()
    app = app_id(api)
    build, build_version = processed_build(api, app, args.build)
    version_string, _ = pubspec_version()
    version = editable_version(api, app, version_string)
    store_version = api.get(f'/v1/appStoreVersions/{version}')['data']['attributes']['versionString']
    if store_version != build_version:
        die(f'the App Store version is {store_version} and build {args.build} is {build_version}; they must match')
    api.call('PATCH', f'/v1/appStoreVersions/{version}/relationships/build', {'data': {'type': 'builds', 'id': build['id']}})
    print(f'  build {args.build} ({build_version}) attached to App Store version {store_version}')


def processed_build(api, app, number):
    """Build [number] once Apple has processed it, and its version number, such as 0.8.164."""
    found = api.get('/v1/builds', **{'filter[app]': app, 'filter[version]': number})['data']
    if not found or found[0]['attributes'].get('processingState') != 'VALID':
        die(f'build {number} is not processed yet')
    build = found[0]
    return build, api.get(f'/v1/builds/{build["id"]}/preReleaseVersion')['data']['attributes']['version']


def cmd_has_build(args):
    """Whether Apple already has build [args.build], for release.yml (ID-468). Apple refuses a build number
    twice, and a build can go up from a manual run, as 534 did for the first submission, before its tag."""
    api = Api()
    found = api.get('/v1/builds', **{'filter[app]': app_id(api), 'filter[version]': args.build})['data']
    print(f'  build {args.build}: ' + ('already in App Store Connect, so it is not uploaded again' if found
                                       else 'not in App Store Connect yet'))
    out = os.environ.get('GITHUB_OUTPUT')
    if out:
        with open(out, 'a', encoding='utf-8') as f:
            f.write(f'uploaded={"true" if found else "false"}\n')


# ── Promotion: Play's tracks, on the App Store (ID-468) ─────────────────────────────────────
#
# promote.yml runs this beside Play's own promotion. Play's internal track is TestFlight's Internal
# group, which gets every build on the tag (ID-465), so there is nothing to promote to. alpha and beta,
# Play's closed and open testing, are the external group below, after Beta App Review. production is
# App Review, then the release. Every step is safe to run again: what is done already is reported.

EXTERNAL_GROUP = 'Family'

# appVersionState, or the older appStoreState Apple still sends beside it.
WITH_APP_REVIEW = {'WAITING_FOR_REVIEW', 'IN_REVIEW', 'READY_FOR_REVIEW', 'WAITING_FOR_EXPORT_COMPLIANCE', 'ACCEPTED'}
RELEASED = {'READY_FOR_SALE', 'READY_FOR_DISTRIBUTION', 'PENDING_APPLE_RELEASE', 'PROCESSING_FOR_DISTRIBUTION',
            'PROCESSING_FOR_APP_STORE'}


def production_step(state, attached, build):
    """What production does next with an App Store version in [state] carrying the build [attached]
    (None for none), to release build [build]: one of attach, submit, wait, release, done or stop,
    and why, for the log."""
    if state in EDITABLE:
        if attached == build:
            return 'submit', f'{state}, with this build attached: send it to App Review'
        return 'attach', f'{state}: attach this build, then send it to App Review'
    if attached != build:
        return 'stop', f'{state}, but with build {attached or "none"}, not this one'
    if state in WITH_APP_REVIEW:
        return 'wait', f'{state}: with App Review already. Run this again once Apple approves it'
    if state == 'PENDING_DEVELOPER_RELEASE':
        return 'release', 'approved, and waiting to be released by hand: release it'
    if state in RELEASED:
        return 'done', f'{state}: released already'
    return 'stop', f'{state}: not a state this knows what to do with'


def testflight_step(state):
    """What alpha or beta does next with a build whose external TestFlight state is [state]: one of
    submit, wait, done or stop, and why."""
    if state == 'READY_FOR_BETA_SUBMISSION':
        return 'submit', 'not sent to Beta App Review yet: send it'
    if state in ('WAITING_FOR_BETA_REVIEW', 'IN_BETA_REVIEW'):
        return 'wait', f'{state}: with Beta App Review already. The group gets it once Apple approves it'
    if state in ('BETA_APPROVED', 'READY_FOR_BETA_TESTING', 'IN_BETA_TESTING'):
        return 'done', f'{state}: approved for external testers'
    return 'stop', f'{state}: it can\'t go to external testers'


def submit_for_review(api, app, version):
    """App Store version [version] into a review submission, and the submission to App Review. An open
    submission is used when there is one, as Apple keeps only one at a time."""
    subs = api.get('/v1/reviewSubmissions', **{'filter[app]': app, 'filter[platform]': 'IOS'})['data']
    open_ = [s for s in subs if s['attributes'].get('state') in ('READY_FOR_REVIEW', 'UNRESOLVED_ISSUES')]
    sub = open_[0]['id'] if open_ else api.post('reviewSubmissions', {'platform': 'IOS'}, {'app': rel('apps', app)})['id']
    items = api.get(f'/v1/reviewSubmissions/{sub}/items', include='appStoreVersion')['data']
    if not any(((i.get('relationships') or {}).get('appStoreVersion') or {}).get('data', {}) == {'type': 'appStoreVersions', 'id': version}
               for i in items):
        api.post('reviewSubmissionItems', None, {'reviewSubmission': rel('reviewSubmissions', sub),
                                                 'appStoreVersion': rel('appStoreVersions', version)})
    api.patch('reviewSubmissions', sub, {'submitted': True})


def build_notes(api, build_id):
    """The build's en-AU TestFlight notes, set by whats-new from the release's Play note."""
    for l in api.get(f'/v1/builds/{build_id}/betaBuildLocalizations')['data']:
        if l['attributes'].get('locale') == LOCALE:
            return (l['attributes'].get('whatsNew') or '').strip()
    return ''


def promote_testflight(api, app, build, number, dry_run):
    groups = [g for g in api.get(f'/v1/apps/{app}/betaGroups')['data']
              if g['attributes'].get('name') == EXTERNAL_GROUP and not g['attributes'].get('isInternalGroup')]
    if not groups:
        die(f'no external TestFlight group "{EXTERNAL_GROUP}"')
    group = groups[0]['id']
    in_group = any(b['id'] == build['id'] for b in api.get(f'/v1/betaGroups/{group}/builds', limit=200)['data'])
    state = api.get(f'/v1/builds/{build["id"]}/buildBetaDetail')['data']['attributes'].get('externalBuildState')
    step, why = testflight_step(state)
    lines = [f'TestFlight group {EXTERNAL_GROUP}: build {number} ' + ('is in it' if in_group else 'is not in it yet'),
             f'Beta App Review: {why}']
    if step == 'stop':
        die('; '.join(lines))
    if dry_run:
        return lines + ['Dry run: nothing was changed.']
    if not in_group:
        api.call('POST', f'/v1/betaGroups/{group}/relationships/builds', {'data': [{'type': 'builds', 'id': build['id']}]})
        lines.append(f'Added build {number} to {EXTERNAL_GROUP}.')
    if step == 'submit':
        api.post('betaAppReviewSubmissions', None, {'build': rel('builds', build['id'])})
        lines.append(f'Sent build {number} to Beta App Review; {EXTERNAL_GROUP} gets it once Apple approves it.')
    return lines


def promote_production(api, app, build, number, build_version, dry_run):
    found = api.get(f'/v1/apps/{app}/appStoreVersions',
                    **{'filter[platform]': 'IOS', 'filter[versionString]': build_version})['data']
    lines = []
    if not found:
        # A later version: made from the last one, whose listing Apple copies, with "What's New" from
        # the build's TestFlight notes, which an update must have.
        notes = build_notes(api, build['id'])
        if not notes:
            die(f'build {number} has no TestFlight notes for "What\'s New"')
        if dry_run:
            return [f'App Store version {build_version}: not made yet. Would make it, with "What\'s New" from '
                    f'build {number}\'s TestFlight notes, attach the build and send it to App Review.',
                    'Dry run: nothing was changed.']
        version = editable_version(api, app, build_version)
        api.patch('appStoreVersions', version, {'versionString': build_version})
        vloc = localization(api, f'/v1/appStoreVersions/{version}/appStoreVersionLocalizations',
                            'appStoreVersionLocalizations', 'appStoreVersion', version, {})
        api.patch('appStoreVersionLocalizations', vloc, {'whatsNew': notes})
        lines.append(f'App Store version {build_version} made, with "What\'s New" from the TestFlight notes.')
    else:
        version = found[0]['id']
    a = api.get(f'/v1/appStoreVersions/{version}')['data']['attributes']
    state = a.get('appVersionState') or a.get('appStoreState')
    attached = (api.get(f'/v1/appStoreVersions/{version}/build').get('data') or {}).get('id')
    step, why = production_step(state, attached, build['id'])
    lines.append(f'App Store version {build_version}: {why}')
    if step == 'stop':
        die('; '.join(lines))
    if dry_run:
        return lines + ['Dry run: nothing was changed.']
    if step == 'attach':
        api.call('PATCH', f'/v1/appStoreVersions/{version}/relationships/build', {'data': {'type': 'builds', 'id': build['id']}})
        lines.append(f'Attached build {number}.')
    if step in ('attach', 'submit'):
        submit_for_review(api, app, version)
        lines.append(f'Sent {build_version} ({number}) to App Review. It is released when approved, or by '
                     'running this again, as the version\'s release option says.')
    if step == 'release':
        api.post('appStoreVersionReleaseRequests', None, {'appStoreVersion': rel('appStoreVersions', version)})
        lines.append(f'Released {build_version} ({number}) on the App Store.')
    return lines


def cmd_promote(args):
    api = Api()
    app = app_id(api)
    build, build_version = processed_build(api, app, args.build)
    if args.to == 'production':
        lines = promote_production(api, app, build, args.build, build_version, args.dry_run)
    else:
        lines = promote_testflight(api, app, build, args.build, args.dry_run)
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    for line in lines:
        print(f'  {line}')
    if summary:
        with open(summary, 'a', encoding='utf-8') as f:
            f.write(f'**App Store, build {args.build} ({build_version}) to {args.to}:** ' + ' '.join(lines) + '\n')


# ── The certificates a CI run makes (ID-469) ────────────────────────────────────────────────
#
# Each runner starts with an empty keychain, so Xcode's automatic signing makes a new Development
# certificate for the archive every run, and nothing ever removed one: 7 by 2026-10-25, against a cap
# Apple puts on how many a team can have. The .ipa is signed with the cloud-managed Distribution
# certificate, which is reused, so the Development one is never needed after the run. release.yml notes
# the team's certificates before the archive and revokes the new Development ones at the end.

DEVELOPMENT_TYPES = {'DEVELOPMENT', 'IOS_DEVELOPMENT', 'MAC_APP_DEVELOPMENT'}


def certificate_ids(api):
    return [c['id'] for c in api.get('/v1/certificates', limit=200)['data']]


def new_certificates(before, now):
    """The certificates in [now] not in [before]: the Development ones to revoke, and any others, which are
    left alone and reported - a Distribution certificate is shared by every run and signs what Apple has."""
    new = [c for c in now if c['id'] not in before]
    dev = [c for c in new if c['attributes'].get('certificateType') in DEVELOPMENT_TYPES]
    return dev, [c for c in new if c not in dev]


def describe(cert):
    a = cert['attributes']
    return f'{a.get("certificateType")} "{a.get("name") or a.get("displayName")}", expires {a.get("expirationDate", "?")[:10]}'


def cmd_note_certificates(args):
    ids = certificate_ids(Api())
    with open(args.to, 'w', encoding='utf-8') as f:
        f.write('\n'.join(ids) + '\n')
    print(f'  {len(ids)} certificates before the archive')


def cmd_revoke_new_certificates(args):
    api = Api()
    with open(args.since, encoding='utf-8') as f:
        before = {line.strip() for line in f if line.strip()}
    dev, other = new_certificates(before, api.get('/v1/certificates', limit=200)['data'])
    for cert in dev:
        api.call('DELETE', f'/v1/certificates/{cert["id"]}')
        print(f'  revoked {describe(cert)}: made by this run, and needed by nothing after it')
    for cert in other:
        print(f'::warning::this run made {describe(cert)}, which is left alone; check it in Certificates, IDs & Profiles')
    if not dev and not other:
        print('  no new certificates')


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)
    l = sub.add_parser('listing')
    l.add_argument('--check', action='store_true')
    sub.add_parser('testers')
    w = sub.add_parser('whats-new')
    w.add_argument('--build', required=True)
    w.add_argument('--notes', required=True)
    a = sub.add_parser('attach-build')
    a.add_argument('--build', required=True)
    h = sub.add_parser('has-build')
    h.add_argument('--build', required=True)
    pr = sub.add_parser('promote')
    pr.add_argument('--build', required=True)
    pr.add_argument('--to', required=True, choices=['alpha', 'beta', 'production'])
    pr.add_argument('--dry-run', action='store_true')
    nc = sub.add_parser('note-certificates')
    nc.add_argument('--to', required=True)
    rc = sub.add_parser('revoke-new-certificates')
    rc.add_argument('--since', required=True)
    args = p.parse_args()
    {'listing': cmd_listing, 'testers': cmd_testers, 'whats-new': cmd_whats_new,
     'attach-build': cmd_attach_build, 'has-build': cmd_has_build, 'promote': cmd_promote,
     'note-certificates': cmd_note_certificates, 'revoke-new-certificates': cmd_revoke_new_certificates}[args.cmd](args)


if __name__ == '__main__':
    main()
