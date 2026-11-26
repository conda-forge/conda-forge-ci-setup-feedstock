"""Sign CEP-27 publish attestations for packages copied to conda-forge.

`upload_or_check_non_existence` calls `attest_packages` right after it copied
packages to the production channel, if conda-forge.yml enables
`github_actions: {attest_packages: true}`. Each package gets one Sigstore
attestation, signed with the OIDC identity of the GitHub Actions workflow and
stored in the GitHub attestation API of the feedstock, where it can be looked
up by the package's SHA-256.

The workflow needs the `id-token: write` and `attestations: write`
permissions, and these environment variables (forwarded into docker on linux):

- `GITHUB_ACTIONS`: set by GitHub Actions.
- `ACTIONS_ID_TOKEN_REQUEST_URL` and `ACTIONS_ID_TOKEN_REQUEST_TOKEN`: set by
  GitHub Actions with `id-token: write`; used by sigstore to get the OIDC
  identity token that the attestations are signed with.
- `GITHUB_REPOSITORY`: set by GitHub Actions; the repository that the
  attestations are stored in.
- `GITHUB_TOKEN`: passed by the workflow (`${{ github.token }}`); used to store
  the attestations.
"""

import json
import os

import requests
from sigstore import dsse
from sigstore.models import ClientTrustConfig
from sigstore.oidc import IdentityToken, detect_credential
from sigstore.sign import SigningContext

PREDICATE_TYPE = "https://schemas.conda.org/attestations-publish-1.schema.json"
REQUIRED_ENV = (
    "ACTIONS_ID_TOKEN_REQUEST_URL",
    "ACTIONS_ID_TOKEN_REQUEST_TOKEN",
    "GITHUB_REPOSITORY",
    "GITHUB_TOKEN",
)


def missing_environment():
    """The environment variables that are needed to attest but not set."""
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return ["GITHUB_ACTIONS"]
    return [name for name in REQUIRED_ENV if not os.environ.get(name)]


def statement(subject):
    return (
        dsse.StatementBuilder()
        .subjects(
            [
                dsse.Subject(
                    name=subject["name"],
                    digest=dsse.DigestSet(root={"sha256": subject["sha256"]}),
                )
            ]
        )
        .predicate_type(PREDICATE_TYPE)
        .predicate({"targetChannel": subject["target_channel"]})
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


def attest_packages(subjects):
    """Sign and store one attestation per subject.

    `subjects` are dicts with the `name` (filename), `sha256` and
    `target_channel` of a package. Never raises: attestations are best effort
    and must not fail an upload. Returns the number of packages that were not
    attested.
    """
    if not subjects:
        return 0

    missing = missing_environment()
    if missing:
        print(
            "WARNING: not attesting {} package(s), because {} not set. The "
            "workflow needs the `id-token: write` and `attestations: write` "
            "permissions.".format(
                len(subjects),
                ", ".join(missing) + (" is" if len(missing) == 1 else " are"),
            )
        )
        return len(subjects)

    try:
        context = SigningContext.from_trust_config(ClientTrustConfig.production())
    except Exception as e:
        print("WARNING: could not set up signing, no attestations: {!r}".format(e))
        return len(subjects)

    failed = 0
    for subject in subjects:
        try:
            # a fresh identity token per package, as they expire quickly
            with context.signer(IdentityToken(detect_credential())) as signer:
                bundle = signer.sign_dsse(statement(subject))
            attestation_id = store_on_github(bundle)
            print(
                f"Attested {subject['name']} for {subject['target_channel']}: "
                f"https://github.com/{os.environ['GITHUB_REPOSITORY']}"
                f"/attestations/{attestation_id}"
            )
        except Exception as e:
            print(f"WARNING: failed to attest {subject['name']}: {e!r}")
            failed += 1
    return failed
