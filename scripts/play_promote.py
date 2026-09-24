#!/usr/bin/env python3
"""play_promote.py - move the release on one Google Play track to another (ID-179).

Run by .github/workflows/promote.yml. It replaces kevin-david/promote-play-release, which still
declares the Node 20 runtime GitHub is retiring and has had no release since April 2025. It does
exactly what that action did with its defaults: open an edit, copy every release on the source
track to the target at full rollout (status completed, in-app update priority 0), commit.

Environment:
  PLAY_JSON      the service account key, raw JSON
  PACKAGE_NAME   the application id
  FROM_TRACK     internal, alpha or beta
  TO_TRACK       alpha, beta or production
  DRY_RUN        "true" to show what would move and change nothing (the edit is thrown away)
"""
import json
import os
import sys

from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

API = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications'


def main() -> None:
    package = os.environ['PACKAGE_NAME']
    source = os.environ['FROM_TRACK']
    target = os.environ['TO_TRACK']
    dry_run = os.environ.get('DRY_RUN') == 'true'

    creds = service_account.Credentials.from_service_account_info(
        json.loads(os.environ['PLAY_JSON']), scopes=['https://www.googleapis.com/auth/androidpublisher'])
    session = AuthorizedSession(creds)

    def call(method: str, path: str, body: dict | None = None) -> dict:
        response = session.request(method, f'{API}/{package}{path}', json=body, timeout=60)
        if response.status_code >= 300:
            sys.exit(f'::error::{method} {path} answered HTTP {response.status_code}: {response.text[:500]}')
        return response.json() if response.text else {}

    edit = call('POST', '/edits')['id']
    releases = call('GET', f'/edits/{edit}/tracks/{source}').get('releases') or []
    if not releases:
        call('DELETE', f'/edits/{edit}')
        sys.exit(f'::error::There is no release on {source} to promote.')

    for release in releases:
        release['status'] = 'completed'
        release['inAppUpdatePriority'] = 0
        release.pop('userFraction', None)
    moving = '; '.join(f"{r.get('name', '(unnamed)')}, version code {', '.join(r.get('versionCodes', []))}" for r in releases)
    print(f'On {source}: {moving}')

    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if dry_run:
        call('DELETE', f'/edits/{edit}')
        line = f'Dry run: would promote {moving} from {source} to {target}. Nothing was changed.'
    else:
        call('PUT', f'/edits/{edit}/tracks/{target}', {'track': target, 'releases': releases})
        call('POST', f'/edits/{edit}:commit')
        line = f'Promoted {moving} from {source} to {target}.'
    print(line)
    if summary:
        with open(summary, 'a', encoding='utf-8') as f:
            f.write(line + '\n')


if __name__ == '__main__':
    main()
