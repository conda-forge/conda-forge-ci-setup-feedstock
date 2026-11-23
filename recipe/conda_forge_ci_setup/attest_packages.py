"""Sign a CEP-27 publish attestation for every package copied to conda-forge.

Reads the attest-subjects-*.json files that `upload_or_check_non_existence`
writes after each copy to the production channel
(`[{"name", "sha256", "target_channel"}]`), signs one Sigstore attestation per
package with the OIDC identity of the GitHub Actions job, and stores it in the
GitHub attestation API of the repository, where it can be looked up by the
package's SHA-256.

It only runs in GitHub Actions, in a job with the `id-token: write` and
`attestations: write` permissions, and reads these environment variables:

- `GITHUB_ACTIONS`: set by GitHub Actions; the command refuses to run without it.
- `ACTIONS_ID_TOKEN_REQUEST_URL` and `ACTIONS_ID_TOKEN_REQUEST_TOKEN`: set by
  GitHub Actions when the job has `id-token: write`; used by sigstore to get
  the OIDC identity token that the attestations are signed with.
- `GITHUB_REPOSITORY`: set by GitHub Actions; the repository that the
  attestations are stored in.
- `GITHUB_TOKEN`: must be passed by the workflow (`${{ github.token }}`); used
  to store the attestations.

sigstore is imported only when there is something to sign, so that the other
commands of conda-forge-ci-setup do not pay for importing it.
"""

import json
import os
import sys
from pathlib import Path

import click
import requests

PREDICATE_TYPE = "https://schemas.conda.org/attestations-publish-1.schema.json"


def read_subjects(directory):
    subjects = {}
    for path in sorted(Path(directory).rglob("attest-subjects*.json")):
        for entry in json.loads(path.read_text()):
            key = (entry["name"], entry["sha256"], entry["target_channel"])
            subjects[key] = entry
    return list(subjects.values())


def statement(entry):
    from sigstore import dsse

    return (
        dsse.StatementBuilder()
        .subjects(
            [
                dsse.Subject(
                    name=entry["name"],
                    digest=dsse.DigestSet(root={"sha256": entry["sha256"]}),
                )
            ]
        )
        .predicate_type(PREDICATE_TYPE)
        .predicate({"targetChannel": entry["target_channel"]})
        .build()
    )


def store_on_github(bundle):
    response = requests.post(
        f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}/attestations",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        json={"bundle": json.loads(bundle.to_json())},
        timeout=60,
    )
    response.raise_for_status()
    return response.json()["id"]


def attest_packages(directory):
    if os.environ.get("GITHUB_ACTIONS") != "true":
        print("This command signs with the OIDC identity of a GitHub Actions job")
        print("and only runs in GitHub Actions.")
        return 1

    subjects = read_subjects(directory)
    if not subjects:
        print("No packages to attest")
        return 0

    from sigstore.models import ClientTrustConfig
    from sigstore.oidc import IdentityToken, detect_credential
    from sigstore.sign import SigningContext

    context = SigningContext.from_trust_config(ClientTrustConfig.production())
    failed = 0
    for entry in subjects:
        try:
            # a fresh identity token per package, as they expire quickly
            with context.signer(IdentityToken(detect_credential())) as signer:
                bundle = signer.sign_dsse(statement(entry))
            attestation_id = store_on_github(bundle)
            print(
                f"Attested {entry['name']} for {entry['target_channel']}: "
                f"https://github.com/{os.environ['GITHUB_REPOSITORY']}"
                f"/attestations/{attestation_id}"
            )
        except Exception as e:
            print(f"Failed to attest {entry['name']}: {e!r}")
            failed = 1

    return failed


@click.command()
@click.argument(
    "directory",
    type=click.Path(exists=True, file_okay=False, dir_okay=True),
)
def main(directory):
    """Attest the packages listed in the attest-subjects-*.json files in DIRECTORY."""
    sys.exit(attest_packages(directory))
