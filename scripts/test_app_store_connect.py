#!/usr/bin/env python3
"""Tests for app_store_connect.py's promotion (ID-468): what each App Store state leads to, and that a
dry run sends nothing. Run by the quality workflow: python3 -m unittest discover -s scripts -p 'test_*.py'.
No key and no network: the API is a fake that answers from a table and records what is sent."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import app_store_connect as asc  # noqa: E402


class FakeApi:
    """GETs answered from [answers] by path; every other call recorded in [sent]."""

    def __init__(self, answers):
        self.answers = answers
        self.sent = []

    def get(self, path, **params):
        if path not in self.answers:
            raise AssertionError(f'unexpected GET {path}')
        return self.answers[path]

    def call(self, method, path, body=None, params=None):
        self.sent.append((method, path))
        return {}

    def patch(self, kind, id_, attributes=None, relationships=None):
        self.sent.append(('PATCH', kind, attributes))
        return {}

    def post(self, kind, attributes, relationships):
        self.sent.append(('POST', kind))
        return {'id': f'new-{kind}'}


BUILD = {'id': 'b534'}


def version_answers(state, attached):
    return {
        '/v1/apps/app/appStoreVersions': {'data': [{'id': 'v1'}]},
        '/v1/appStoreVersions/v1': {'data': {'attributes': {'appVersionState': state}}},
        '/v1/appStoreVersions/v1/build': {'data': {'id': attached} if attached else None},
        '/v1/reviewSubmissions': {'data': []},
        '/v1/reviewSubmissions/new-reviewSubmissions/items': {'data': []},
        '/v1/appStoreVersions/v1/appStoreVersionLocalizations': {
            'data': [{'id': 'vl1', 'attributes': {'locale': 'en-AU', 'whatsNew': 'Notes.'}}]},
    }


class ProductionStep(unittest.TestCase):
    def test_each_state(self):
        cases = [
            ('PREPARE_FOR_SUBMISSION', None, 'attach'),
            ('PREPARE_FOR_SUBMISSION', 'b530', 'attach'),
            ('PREPARE_FOR_SUBMISSION', 'b534', 'submit'),
            ('REJECTED', 'b534', 'submit'),
            ('WAITING_FOR_REVIEW', 'b534', 'wait'),
            ('IN_REVIEW', 'b534', 'wait'),
            ('PENDING_DEVELOPER_RELEASE', 'b534', 'release'),
            ('READY_FOR_SALE', 'b534', 'done'),
            ('READY_FOR_DISTRIBUTION', 'b534', 'done'),
            # Past the point of changing its build, and carrying another: never released in this one's name.
            ('WAITING_FOR_REVIEW', 'b530', 'stop'),
            ('PENDING_DEVELOPER_RELEASE', 'b530', 'stop'),
            ('SOMETHING_NEW', 'b534', 'stop'),
        ]
        for state, attached, step in cases:
            with self.subTest(state=state, attached=attached):
                self.assertEqual(asc.production_step(state, attached, 'b534')[0], step)


class TestflightStep(unittest.TestCase):
    def test_each_state(self):
        cases = [
            ('READY_FOR_BETA_SUBMISSION', 'submit'),
            ('WAITING_FOR_BETA_REVIEW', 'wait'),
            ('IN_BETA_REVIEW', 'wait'),
            ('BETA_APPROVED', 'done'),
            ('IN_BETA_TESTING', 'done'),
            ('BETA_REJECTED', 'stop'),
            ('EXPIRED', 'stop'),
            (None, 'stop'),
        ]
        for state, step in cases:
            with self.subTest(state=state):
                self.assertEqual(asc.testflight_step(state)[0], step)


class PromoteProduction(unittest.TestCase):
    def run_it(self, state, attached, dry_run):
        api = FakeApi(version_answers(state, attached))
        lines = asc.promote_production(api, 'app', BUILD, '534', '0.8.164', dry_run)
        return api, lines

    def test_a_dry_run_sends_nothing(self):
        for state in ('PREPARE_FOR_SUBMISSION', 'PENDING_DEVELOPER_RELEASE'):
            with self.subTest(state=state):
                api, lines = self.run_it(state, 'b534', dry_run=True)
                self.assertEqual(api.sent, [])
                self.assertIn('Dry run: nothing was changed.', lines)

    def test_an_unsubmitted_version_gets_the_build_and_goes_to_review(self):
        api, _ = self.run_it('PREPARE_FOR_SUBMISSION', None, dry_run=False)
        self.assertEqual(api.sent, [
            ('PATCH', '/v1/appStoreVersions/v1/relationships/build'),
            ('POST', 'reviewSubmissions'),
            ('POST', 'reviewSubmissionItems'),
            ('PATCH', 'reviewSubmissions', {'submitted': True}),
        ])

    def test_a_version_with_app_review_is_left_alone(self):
        api, lines = self.run_it('WAITING_FOR_REVIEW', 'b534', dry_run=False)
        self.assertEqual(api.sent, [])
        self.assertIn('with App Review already', lines[-1])

    def test_an_approved_manual_release_is_released(self):
        api, _ = self.run_it('PENDING_DEVELOPER_RELEASE', 'b534', dry_run=False)
        self.assertEqual(api.sent, [('POST', 'appStoreVersionReleaseRequests')])

    def test_another_build_stops_the_run(self):
        with self.assertRaises(SystemExit):
            self.run_it('PENDING_DEVELOPER_RELEASE', 'b530', dry_run=False)


class PromoteTestflight(unittest.TestCase):
    def answers(self, state, in_group):
        return {
            '/v1/apps/app/betaGroups': {'data': [
                {'id': 'gi', 'attributes': {'name': 'Internal', 'isInternalGroup': True}},
                {'id': 'gf', 'attributes': {'name': asc.EXTERNAL_GROUP, 'isInternalGroup': False}},
            ]},
            '/v1/betaGroups/gf/builds': {'data': [{'id': 'b534'}] if in_group else []},
            '/v1/builds/b534/buildBetaDetail': {'data': {'attributes': {'externalBuildState': state}}},
        }

    def test_a_new_build_joins_the_group_and_goes_to_beta_review(self):
        api = FakeApi(self.answers('READY_FOR_BETA_SUBMISSION', in_group=False))
        asc.promote_testflight(api, 'app', BUILD, '534', dry_run=False)
        self.assertEqual(api.sent, [('POST', '/v1/betaGroups/gf/relationships/builds'), ('POST', 'betaAppReviewSubmissions')])

    def test_a_second_run_changes_nothing(self):
        api = FakeApi(self.answers('WAITING_FOR_BETA_REVIEW', in_group=True))
        asc.promote_testflight(api, 'app', BUILD, '534', dry_run=False)
        self.assertEqual(api.sent, [])

    def test_a_dry_run_sends_nothing(self):
        api = FakeApi(self.answers('READY_FOR_BETA_SUBMISSION', in_group=False))
        lines = asc.promote_testflight(api, 'app', BUILD, '534', dry_run=True)
        self.assertEqual(api.sent, [])
        self.assertIn('Dry run: nothing was changed.', lines)

    def groups(self, name):
        return {'/v1/apps/app/betaGroups': {'data': [{'id': 'gx', 'attributes': {'name': name, 'isInternalGroup': False}}]},
                '/v1/betaGroups/gx/builds': {'data': []},
                '/v1/builds/b534/buildBetaDetail': {'data': {'attributes': {'externalBuildState': 'READY_FOR_BETA_SUBMISSION'}}}}

    def test_the_external_group_is_family_and_friends(self):
        # Andrew's group in App Store Connect since 2026-11-08, when Family was deleted (ID-542).
        api = FakeApi(self.groups('Family and friends'))
        asc.promote_testflight(api, 'app', BUILD, '534', dry_run=False)
        self.assertEqual(api.sent, [('POST', '/v1/betaGroups/gx/relationships/builds'), ('POST', 'betaAppReviewSubmissions')])

    def test_the_deleted_family_group_is_not_used(self):
        with self.assertRaises(SystemExit):
            asc.promote_testflight(FakeApi(self.groups('Family')), 'app', BUILD, '534', dry_run=False)



def cert(id_, kind):
    return {'id': id_, 'attributes': {'certificateType': kind, 'name': f'cert {id_}', 'expirationDate': '2027-10-25T00:00:00.000+0000'}}


class NewCertificates(unittest.TestCase):
    """ID-469: a run revokes the Development certificate it made, and nothing else."""

    BEFORE = [cert('andrew', 'DEVELOPMENT'), cert('managed', 'DISTRIBUTION')]

    def test_only_new_development_certificates_are_revoked(self):
        now = self.BEFORE + [cert('run', 'DEVELOPMENT'), cert('run-ios', 'IOS_DEVELOPMENT'), cert('new-dist', 'DISTRIBUTION')]
        dev, other = asc.new_certificates({'andrew', 'managed'}, now)
        self.assertEqual([c['id'] for c in dev], ['run', 'run-ios'])
        self.assertEqual([c['id'] for c in other], ['new-dist'])

    def test_nothing_new_revokes_nothing(self):
        self.assertEqual(asc.new_certificates({'andrew', 'managed'}, self.BEFORE), ([], []))

    def run_revoke(self, now):
        import tempfile
        api = FakeApi({'/v1/certificates': {'data': now}})
        with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as f:
            f.write('andrew\nmanaged\n')
        real, asc.Api = asc.Api, lambda: api
        try:
            asc.cmd_revoke_new_certificates(type('Args', (), {'since': f.name}))
        finally:
            asc.Api = real
            os.unlink(f.name)
        return api.sent

    def test_the_command_deletes_the_run_s_development_certificate_only(self):
        sent = self.run_revoke(self.BEFORE + [cert('run', 'DEVELOPMENT'), cert('new-dist', 'DISTRIBUTION')])
        self.assertEqual(sent, [('DELETE', '/v1/certificates/run')])

    def test_the_command_leaves_andrews_own_and_the_shared_distribution_one(self):
        self.assertEqual(self.run_revoke(self.BEFORE), [])


class ReleaseWorkflowCertificates(unittest.TestCase):
    """ID-469: release.yml notes the certificates before the archive, and revokes the run's own after the
    last export, even when a step between failed."""

    def setUp(self):
        with open(os.path.join(asc.ROOT, '.github', 'workflows', 'release.yml'), encoding='utf-8') as f:
            self.yml = f.read()

    def at(self, text):
        i = self.yml.find(text)
        self.assertNotEqual(i, -1, text)
        return i

    def test_noted_before_the_archive_and_revoked_after_the_upload(self):
        note = self.at('app_store_connect.py note-certificates --to')
        revoke = self.at('app_store_connect.py revoke-new-certificates --since')
        self.assertLess(note, self.at('- name: Archive, signed with the team'))
        self.assertGreater(revoke, self.at('- name: Upload to App Store Connect for TestFlight'))
        self.assertLess(revoke, self.at('- name: Remove the App Store Connect key'))

    def test_the_revoke_runs_whatever_happened_after_the_note(self):
        step = self.yml[self.yml.rfind('- name:', 0, self.at('revoke-new-certificates --since')):]
        self.assertIn("if: ${{ always() && steps.certificates.outcome == 'success' }}", step.split('run:')[0])


# Every attribute of Apple's AgeRatingDeclaration, from its documentation, read 2026-11-03.
APPLE_AGE_ATTRIBUTES = [
    'advertising', 'alcoholTobaccoOrDrugUseOrReferences', 'contests', 'gambling', 'gamblingSimulated',
    'gunsOrOtherWeapons', 'healthOrWellnessTopics', 'kidsAgeBand', 'lootBox', 'medicalOrTreatmentInformation',
    'messagingAndChat', 'parentalControls', 'profanityOrCrudeHumor', 'ageAssurance', 'sexualContentGraphicAndNudity',
    'sexualContentOrNudity', 'socialMedia', 'socialMediaAgeRestricted', 'horrorOrFearThemes', 'matureOrSuggestiveThemes',
    'unrestrictedWebAccess', 'userGeneratedContent', 'violenceCartoonOrFantasy',
    'violenceRealisticProlongedGraphicOrSadistic', 'violenceRealistic', 'ageRatingOverride', 'ageRatingOverrideV2',
    'koreaAgeRatingOverride', 'gracRatingClassificationNumber', 'developerAgeRatingInfoUrl',
]


class AgeRating(unittest.TestCase):
    """ID-510: every age rating question Apple asks is answered None or No, and one it adds is reported."""

    def test_every_question_apple_asks_is_answered(self):
        answers, unknown = asc.age_answers({k: None for k in APPLE_AGE_ATTRIBUTES})
        self.assertEqual(unknown, [])
        self.assertIs(answers['socialMedia'], False)
        self.assertIs(answers['socialMediaAgeRestricted'], False)
        self.assertEqual(answers['violenceRealistic'], 'NONE')

    def test_overrides_are_left_as_they_are(self):
        answers, _ = asc.age_answers({k: None for k in APPLE_AGE_ATTRIBUTES})
        self.assertFalse(asc.AGE_NOT_ASKED & set(answers))

    def test_a_question_apple_adds_is_reported(self):
        answers, unknown = asc.age_answers({'socialMedia': None, 'someNewQuestion': None})
        self.assertEqual(answers, {'socialMedia': False})
        self.assertEqual(unknown, ['someNewQuestion'])

    def test_only_the_questions_apple_returns_are_sent(self):
        answers, _ = asc.age_answers({'contests': None})
        self.assertEqual(answers, {'contests': 'NONE'})


class LiveAppApi(FakeApi):
    """App Store Connect for an app on sale (ID-549): only the live app info is there until a new version
    is made, and Apple refuses any change to the live app info's localization."""

    def __init__(self):
        super().__init__({
            '/v1/apps/app/appStoreVersions': {'data': [{'id': 'live', 'attributes': {'appVersionState': 'READY_FOR_SALE'}}]},
            '/v1/appInfos/info-live/appInfoLocalizations': {'data': [{'id': 'loc-live', 'attributes': {'locale': 'en-AU'}}]},
            '/v1/appInfos/info-next/appInfoLocalizations': {'data': [{'id': 'loc-next', 'attributes': {'locale': 'en-AU'}}]},
            '/v1/appInfos/info-live/ageRatingDeclaration': {'data': {'id': 'age-live', 'attributes': {}}},
            '/v1/appInfos/info-next/ageRatingDeclaration': {'data': {'id': 'age-next', 'attributes': {}}},
            '/v1/appStoreVersions/new-appStoreVersions/appStoreVersionLocalizations': {'data': []},
            '/v1/appStoreVersions/new-appStoreVersions/appStoreReviewDetail': {'data': None},
        })
        self.version_made = False

    def get(self, path, **params):
        if path == '/v1/apps/app/appInfos':
            live = {'id': 'info-live', 'attributes': {'state': 'READY_FOR_DISTRIBUTION'}}
            nxt = {'id': 'info-next', 'attributes': {'state': 'PREPARE_FOR_SUBMISSION'}}
            return {'data': [nxt, live] if self.version_made else [live]}
        return super().get(path, **params)

    def patch(self, kind, id_, attributes=None, relationships=None):
        if (kind, id_) == ('appInfoLocalizations', 'loc-live'):
            raise AssertionError("HTTP 409: The field 'name' can not be modified in the current state.")
        return super().patch(kind, id_, attributes, relationships)

    def post(self, kind, attributes, relationships):
        if kind == 'appStoreVersions':
            self.version_made = True
        return super().post(kind, attributes, relationships)


LISTING_PLAN = {
    'fields': {'Name': 'cfg-pia-wg', 'Subtitle': 'sub', 'Privacy policy URL': 'https://example.com/p',
               'Primary category': 'Utilities', 'Secondary category': 'Productivity', 'Copyright': '2026 A',
               'Keywords': 'k', 'Promotional text': 'p', 'Support URL': 'https://example.com/s',
               'Marketing URL': 'https://example.com/m'},
    'description': 'd', 'notes': 'n', 'screenshots': {},
}


class ListingOnALiveApp(unittest.TestCase):
    """ID-549: run 42921606900 stopped at the app info, because the version that unlocks it came later."""

    def test_the_next_version_is_made_before_the_app_info_is_changed(self):
        api = LiveAppApi()
        asc.publish_listing(api, 'app', LISTING_PLAN, '0.8.203')
        self.assertIn(('PATCH', 'appInfoLocalizations', {'name': 'cfg-pia-wg', 'subtitle': 'sub',
                                                         'privacyPolicyUrl': 'https://example.com/p'}), api.sent)
        kinds = [s[1] for s in api.sent]
        self.assertLess(kinds.index('appStoreVersions'), kinds.index('appInfoLocalizations'))


class WhatsNewOnAVersionMadeElsewhere(unittest.TestCase):
    """ID-549: a version the listing run or a person made has no What's New, which Apple needs for an update."""

    def run_it(self, whats_new, notes):
        answers = version_answers('PREPARE_FOR_SUBMISSION', None)
        answers['/v1/appStoreVersions/v1/appStoreVersionLocalizations'] = {
            'data': [{'id': 'vl1', 'attributes': {'locale': 'en-AU', 'whatsNew': whats_new}}]}
        answers['/v1/builds/b534/betaBuildLocalizations'] = {
            'data': [{'attributes': {'locale': 'en-AU', 'whatsNew': notes}}]}
        api = FakeApi(answers)
        asc.promote_production(api, 'app', BUILD, '534', '0.8.164', dry_run=False)
        return api

    def test_an_empty_one_is_filled_from_the_testflight_notes_before_submission(self):
        api = self.run_it(None, '• Fixed: something.')
        self.assertEqual(api.sent[0], ('PATCH', 'appStoreVersionLocalizations', {'whatsNew': '• Fixed: something.'}))
        self.assertEqual(api.sent[-1], ('PATCH', 'reviewSubmissions', {'submitted': True}))

    def test_one_already_written_is_kept(self):
        api = self.run_it('Written by hand.', '• Fixed: something.')
        self.assertNotIn('appStoreVersionLocalizations', [s[1] for s in api.sent])

    def test_no_notes_anywhere_stops_before_anything_is_sent(self):
        with self.assertRaises(SystemExit):
            self.run_it('', '')


if __name__ == '__main__':
    unittest.main()
