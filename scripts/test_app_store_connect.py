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


if __name__ == '__main__':
    unittest.main()
