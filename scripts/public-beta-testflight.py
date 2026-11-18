#!/usr/bin/python3
"""Configure and submit Clove's external TestFlight Public Beta via App Store Connect.

Reuses scripts/release-testflight.py for config resolution, JWT generation,
HTTPS-only App Store Connect requests, and secret redaction.

    python3 scripts/public-beta-testflight.py --config ~/.config/apple/clove-testflight.json --inspect
    python3 scripts/public-beta-testflight.py --config ~/.config/apple/clove-testflight.json --prepare --feedback-email mrtoniliu@gmail.com
    python3 scripts/public-beta-testflight.py --config ~/.config/apple/clove-testflight.json --submit --feedback-email mrtoniliu@gmail.com
"""

import argparse
import importlib.util
import re
import sys
import time
import urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_GROUP_NAME = "Clove Public Beta"
MATERIALS_DOC = ROOT / "docs" / "testflight-external.md"
PROJECT_YML = ROOT / "project.yml"
PRIMARY_LOCALE = "en-US"
SECONDARY_LOCALES = ("zh-Hans", "zh-Hant")
TARGET_LOCALES = (PRIMARY_LOCALE, *SECONDARY_LOCALES)
REQUIRED_REVIEW_CONTACT_FIELDS = (
    "contactFirstName",
    "contactLastName",
    "contactPhone",
    "contactEmail",
)
SENSITIVE_REVIEW_FIELDS = (
    "contactPhone",
    "contactEmail",
    "demoAccountPassword",
)
MAX_ASC_TEXT_LENGTH = 4000
DEFAULT_WAIT_SECONDS = 300
POLL_INTERVAL_SECONDS = 15


def _load_release_module():
    module_name = "release_testflight"
    existing = sys.modules.get(module_name)
    if existing is not None:
        return existing
    module_path = Path(__file__).resolve().parent / "release-testflight.py"
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


release = _load_release_module()
ReleaseError = release.ReleaseError
AscHttpError = release.AscHttpError
CLOVE = release.APPS["clove"]


def default_marketing_version(project_yml=PROJECT_YML):
    """Read MARKETING_VERSION from project.yml, falling back to '0.1.0'."""
    if not Path(project_yml).is_file():
        return "0.1.0"
    text = Path(project_yml).read_text(encoding="utf-8")
    match = re.search(r'^\s*MARKETING_VERSION:\s*"?(\d+(?:\.\d+){0,2})"?\s*$', text, re.MULTILINE)
    return match.group(1) if match else "0.1.0"


def asc_config(path):
    """Load App Store Connect API credentials without requiring local .p12 signing assets."""
    path = Path(path)
    if not path.is_file():
        raise ReleaseError(f"Missing {path}; copy Config/TestFlight.local.json.example "
                           "and fill it in, or pass --config")
    if path.stat().st_mode & 0o077:
        raise ReleaseError(f"Restrict {path} to your user: chmod 600 {path}")
    config = release.read_json_config(path)
    if not isinstance(config, dict):
        raise ReleaseError(f"Incomplete TestFlight config: {path}")
    for key in ("apiKeyId", "issuerId", "apiKeyPath"):
        if not isinstance(config.get(key), str) or not config[key].strip():
            raise ReleaseError(f"Incomplete TestFlight config: {path} needs {key}")
    # Register IDs before path validation so path errors redact the key ID.
    release.register_secret(config["apiKeyId"])
    release.register_secret(config["issuerId"])
    config["apiKeyPath"] = release.signing_file(config["apiKeyPath"], "apiKeyPath", secret=True)
    password_file = config.get("distributionP12PasswordFile")
    if isinstance(password_file, str) and password_file.strip():
        candidate = Path(password_file).expanduser().resolve()
        if candidate.is_file() and release.ROOT != candidate and release.ROOT not in candidate.parents:
            if not (candidate.stat().st_mode & 0o077):
                p12_password = candidate.read_text().rstrip("\r\n")
                if p12_password:
                    release.register_secret(p12_password)
    return config


def _extract_fenced_blocks(text):
    """Extract fenced ```text blocks keyed by (section_h2, subsection_h3_or_none)."""
    sections = {}
    h2 = None
    h3 = None
    in_fence = False
    fence_lines = []
    for line in text.splitlines():
        if not in_fence:
            if line.startswith("## "):
                h2 = line[3:].strip()
                h3 = None
            elif line.startswith("### "):
                h3 = line[4:].strip()
            elif line.strip() == "```text":
                in_fence = True
                fence_lines = []
        else:
            if line.strip() == "```":
                in_fence = False
                if h2 is not None:
                    sections[(h2, h3)] = "\n".join(fence_lines).strip()
            else:
                fence_lines.append(line)
    if in_fence:
        raise ReleaseError("Unclosed ```text block in external TestFlight materials")
    return sections


def load_external_materials(path=MATERIALS_DOC):
    """Load en-US, zh-Hans, zh-Hant copy and review notes from docs/testflight-external.md."""
    doc_path = Path(path)
    if not doc_path.is_file():
        raise ReleaseError(f"Missing external TestFlight materials file: {doc_path}")
    blocks = _extract_fenced_blocks(doc_path.read_text(encoding="utf-8"))
    descriptions = {}
    whats_new = {}
    for locale in TARGET_LOCALES:
        desc = blocks.get(("Beta description", locale), "")
        if not desc:
            raise ReleaseError(f"Missing Beta description for {locale} in {doc_path}")
        if len(desc) > MAX_ASC_TEXT_LENGTH:
            raise ReleaseError(f"Beta description for {locale} exceeds {MAX_ASC_TEXT_LENGTH} characters")
        descriptions[locale] = desc

        wn = blocks.get(("What to test", locale), "")
        if not wn:
            raise ReleaseError(f"Missing What to test for {locale} in {doc_path}")
        if len(wn) > MAX_ASC_TEXT_LENGTH:
            raise ReleaseError(f"What to test for {locale} exceeds {MAX_ASC_TEXT_LENGTH} characters")
        whats_new[locale] = wn

    review_notes = blocks.get(("Beta App Review notes", None), "")
    if not review_notes:
        raise ReleaseError(f"Missing Beta App Review notes in {doc_path}")
    if len(review_notes) > MAX_ASC_TEXT_LENGTH:
        raise ReleaseError(f"Beta App Review notes exceed {MAX_ASC_TEXT_LENGTH} characters")

    return {
        "descriptions": descriptions,
        "whats_new": whats_new,
        "review_notes": review_notes,
    }


def validate_feedback_email(value):
    email = (value or "").strip()
    if not email or "@" not in email or email.startswith("<") or " " in email:
        raise ReleaseError(f"Invalid feedback email: {value!r}")
    return email


def list_ios_builds(token, app_id):
    """Return every uploaded iOS build with id, marketingVersion, version, processingState, uploadedDate."""
    params = {
        "filter[app]": app_id,
        "sort": "-uploadedDate",
        "limit": 200,
        "fields[builds]": "version,processingState,uploadedDate,preReleaseVersion",
        "include": "preReleaseVersion",
        "fields[preReleaseVersions]": "version,platform",
    }
    builds = []
    for page in release.asc_pages("builds", params, token):
        versions = {
            item["id"]: (item.get("attributes") or {}).get("version", "")
            for item in page.get("included") or []
            if item.get("type") == "preReleaseVersions"
            and (item.get("attributes") or {}).get("platform") == "IOS"
        }
        for build in page.get("data") or []:
            rel = ((build.get("relationships") or {}).get("preReleaseVersion") or {}).get("data")
            if not rel or rel.get("id") not in versions:
                continue
            attrs = build.get("attributes") or {}
            builds.append({
                "id": build["id"],
                "marketingVersion": versions[rel["id"]],
                "version": str(attrs.get("version", "")),
                "processingState": attrs.get("processingState", ""),
                "uploadedDate": attrs.get("uploadedDate", ""),
            })
    return builds


def list_beta_groups(token, app_id):
    params = {
        "filter[app]": app_id,
        "limit": 200,
        "fields[betaGroups]": (
            "name,isInternalGroup,hasAccessToAllBuilds,"
            "publicLinkEnabled,publicLink,publicLinkLimitEnabled,publicLinkLimit,feedbackEnabled"
        ),
    }
    groups = []
    for page in release.asc_pages("betaGroups", params, token):
        groups.extend(page.get("data") or [])
    return groups


def list_beta_app_localizations(token, app_id):
    params = {
        "filter[app]": app_id,
        "limit": 200,
        "fields[betaAppLocalizations]": "locale,description,feedbackEmail",
    }
    items = []
    for page in release.asc_pages("betaAppLocalizations", params, token):
        items.extend(page.get("data") or [])
    return items


def register_review_secrets(detail):
    """Register all personal contact and demo credential fields for redaction."""
    attrs = (detail or {}).get("attributes") or {}
    for field in SENSITIVE_REVIEW_FIELDS:
        value = attrs.get(field)
        if isinstance(value, str) and value.strip():
            release.register_secret(value)
            release.register_secret(value.strip())


def fetch_beta_app_review_detail(token, app_id):
    response = release.asc_get(f"apps/{app_id}/betaAppReviewDetail", {}, token)
    detail = response.get("data")
    if not detail:
        raise ReleaseError(f"Missing betaAppReviewDetail for app {app_id}")
    register_review_secrets(detail)
    return detail


def review_contact_missing_fields(detail):
    attrs = (detail or {}).get("attributes") or {}
    return [
        field for field in REQUIRED_REVIEW_CONTACT_FIELDS
        if not isinstance(attrs.get(field), str) or not attrs[field].strip()
    ]


def _is_secondary_locale_error(error):
    return isinstance(error, AscHttpError) and error.status_code in (400, 409, 422)


def upsert_beta_app_localizations(token, app_id, descriptions, feedback_email):
    existing = list_beta_app_localizations(token, app_id)
    by_locale = {}
    for item in existing:
        locale = (item.get("attributes") or {}).get("locale")
        if locale:
            by_locale[locale] = item

    results = {}
    # Update existing locales first, then create missing target locales.
    ordered_locales = list(by_locale.keys())
    for locale in TARGET_LOCALES:
        if locale not in by_locale:
            ordered_locales.append(locale)

    for locale in ordered_locales:
        if locale in descriptions:
            description = descriptions[locale]
        elif locale.startswith("en"):
            description = descriptions[PRIMARY_LOCALE]
        else:
            description = None

        existing_item = by_locale.get(locale)
        try:
            if existing_item is not None:
                attributes = {"feedbackEmail": feedback_email}
                if description is not None:
                    attributes["description"] = description
                payload = {
                    "data": {
                        "type": "betaAppLocalizations",
                        "id": existing_item["id"],
                        "attributes": attributes,
                    }
                }
                response = release.asc_patch(f"betaAppLocalizations/{existing_item['id']}", payload, token)
                results[locale] = ("updated", (response.get("data") or {}).get("id", existing_item["id"]))
                print(f"betaAppLocalizations[{locale}]: updated")
            else:
                payload = {
                    "data": {
                        "type": "betaAppLocalizations",
                        "attributes": {
                            "locale": locale,
                            "description": description,
                            "feedbackEmail": feedback_email,
                        },
                        "relationships": {
                            "app": {
                                "data": {"type": "apps", "id": app_id},
                            },
                        },
                    }
                }
                response = release.asc_post("betaAppLocalizations", payload, token)
                loc_id = (response.get("data") or {}).get("id", "")
                results[locale] = ("created", loc_id)
                print(f"betaAppLocalizations[{locale}]: created")
        except AscHttpError as error:
            if locale in SECONDARY_LOCALES and _is_secondary_locale_error(error):
                results[locale] = ("skipped", release.scrub(error))
                print(f"WARNING: App Store Connect rejected betaAppLocalizations locale {locale!r}; "
                      f"continuing ({release.scrub(error)})")
            else:
                raise
    return results


def configure_beta_app_review_detail(token, app_id, review_notes):
    detail = fetch_beta_app_review_detail(token, app_id)
    missing = review_contact_missing_fields(detail)
    if missing:
        raise ReleaseError(
            "Beta App Review contact information is incomplete in App Store Connect "
            f"(missing: {', '.join(missing)}). Fill in the contact fields in App Store Connect first."
        )
    detail_id = detail["id"]
    payload = {
        "data": {
            "type": "betaAppReviewDetails",
            "id": detail_id,
            "attributes": {
                "demoAccountRequired": False,
                "notes": review_notes,
            },
        }
    }
    response = release.asc_patch(f"betaAppReviewDetails/{detail_id}", payload, token)
    updated = response.get("data") or detail
    register_review_secrets(updated)
    print("betaAppReviewDetails: updated (contactComplete: True, demoAccountRequired: False)")
    return updated


def _public_link_attributes(public_link_limit):
    if public_link_limit is None:
        return {"publicLinkEnabled": True, "publicLinkLimitEnabled": False}
    return {
        "publicLinkEnabled": True,
        "publicLinkLimitEnabled": True,
        "publicLinkLimit": public_link_limit,
    }


def _patch_group_with_fallback(token, group, public_link_limit):
    group_id = group["id"]
    attrs = group.get("attributes") or {}
    desired = {
        "feedbackEnabled": True,
        **_public_link_attributes(public_link_limit),
    }
    try:
        response = release.asc_patch(
            f"betaGroups/{group_id}",
            {"data": {"type": "betaGroups", "id": group_id, "attributes": desired}},
            token,
        )
        return response.get("data") or group
    except AscHttpError as error:
        if error.status_code not in (400, 409, 422):
            raise
        print("Note: App Store Connect deferred enabling publicLinkEnabled on group "
              f"{attrs.get('name', group_id)!r} ({release.scrub(error)}). "
              "Public links often require an attached or review-approved build first.")
        if attrs.get("feedbackEnabled") is not True:
            response = release.asc_patch(
                f"betaGroups/{group_id}",
                {
                    "data": {
                        "type": "betaGroups",
                        "id": group_id,
                        "attributes": {"feedbackEnabled": True},
                    }
                },
                token,
            )
            return response.get("data") or group
        return group


def ensure_external_beta_group(token, app_id, group_name, public_link_limit=None):
    groups = list_beta_groups(token, app_id)
    matches = [g for g in groups if (g.get("attributes") or {}).get("name") == group_name]
    if len(matches) > 1:
        raise ReleaseError(f"Expected at most one betaGroup named {group_name!r}, found {len(matches)}")
    if matches:
        group = matches[0]
        attrs = group.get("attributes") or {}
        if attrs.get("isInternalGroup"):
            raise ReleaseError(f"Beta group {group_name!r} is internal; expected an external group")
        print(f"betaGroups[{group_name}]: found existing external group (id={group['id']})")
    else:
        payload = {
            "data": {
                "type": "betaGroups",
                "attributes": {
                    "name": group_name,
                    "isInternalGroup": False,
                    "feedbackEnabled": True,
                },
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}},
                },
            }
        }
        response = release.asc_post("betaGroups", payload, token)
        group = response.get("data")
        if not group or not group.get("id"):
            raise ReleaseError(f"App Store Connect created betaGroup {group_name!r} without an ID")
        print(f"betaGroups[{group_name}]: created external group (id={group['id']})")

    group = _patch_group_with_fallback(token, group, public_link_limit)
    attrs = group.get("attributes") or {}
    print(
        f"betaGroups[{group_name}] state: "
        f"isInternalGroup={attrs.get('isInternalGroup')}, "
        f"feedbackEnabled={attrs.get('feedbackEnabled')}, "
        f"publicLinkEnabled={attrs.get('publicLinkEnabled')}, "
        f"publicLinkLimitEnabled={attrs.get('publicLinkLimitEnabled')}, "
        f"publicLinkLimit={attrs.get('publicLinkLimit')}, "
        f"publicLink={attrs.get('publicLink') or '(not assigned yet)'}"
    )
    return group


def _build_sort_key(build):
    version = build.get("version", "")
    numeric = int(version) if version.isdecimal() else -1
    return (numeric, build.get("uploadedDate", ""))


def resolve_target_build(
    token,
    app_id,
    marketing_version,
    *,
    build_number=None,
    wait_seconds=DEFAULT_WAIT_SECONDS,
    poll_interval=POLL_INTERVAL_SECONDS,
    sleep_fn=time.sleep,
):
    builds = [
        b for b in list_ios_builds(token, app_id)
        if b["marketingVersion"] == marketing_version
    ]
    if not builds:
        raise ReleaseError(f"No uploaded iOS builds found for {CLOVE.bundle_id} {marketing_version}")

    if build_number is not None:
        matching = [b for b in builds if b["version"] == str(build_number)]
        if not matching:
            raise ReleaseError(
                f"Build {build_number} not found for {CLOVE.bundle_id} {marketing_version}"
            )
        target = max(matching, key=_build_sort_key)
    else:
        valid_builds = [b for b in builds if b["processingState"] == "VALID"]
        if valid_builds:
            target = max(valid_builds, key=_build_sort_key)
        else:
            processing_builds = [b for b in builds if b["processingState"] == "PROCESSING"]
            if processing_builds and wait_seconds > 0:
                target = max(processing_builds, key=_build_sort_key)
            else:
                states = ", ".join(f"{b['version']}={b['processingState']}" for b in builds[:5])
                raise ReleaseError(
                    f"No VALID build found for {CLOVE.bundle_id} {marketing_version} (recent: {states})"
                )

    deadline = time.monotonic() + max(wait_seconds, 0)
    while target["processingState"] == "PROCESSING":
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ReleaseError(
                f"Build {target['version']} ({marketing_version}) is still PROCESSING after waiting"
            )
        print(f"Waiting for build {target['version']} ({marketing_version}) processingState=VALID...")
        sleep_fn(min(poll_interval, remaining))
        refreshed = release.asc_get(
            f"builds/{target['id']}",
            {"fields[builds]": "version,processingState,uploadedDate"},
            token,
        )
        attrs = (refreshed.get("data") or {}).get("attributes") or {}
        target = {
            **target,
            "processingState": attrs.get("processingState", target["processingState"]),
            "version": str(attrs.get("version", target["version"])),
        }

    if target["processingState"] != "VALID":
        raise ReleaseError(
            f"Build {target['version']} ({marketing_version}) has processingState={target['processingState']!r}, expected 'VALID'"
        )
    print(f"Target build: {marketing_version} ({target['version']}), id={target['id']}, processingState=VALID")
    return target


def list_beta_build_localizations(token, build_id):
    params = {
        "filter[build]": build_id,
        "limit": 200,
        "fields[betaBuildLocalizations]": "locale,whatsNew",
    }
    items = []
    for page in release.asc_pages("betaBuildLocalizations", params, token):
        items.extend(page.get("data") or [])
    return items


def upsert_beta_build_localizations(token, build_id, whats_new):
    existing = list_beta_build_localizations(token, build_id)
    by_locale = {
        (item.get("attributes") or {}).get("locale"): item
        for item in existing
        if (item.get("attributes") or {}).get("locale")
    }
    results = {}
    for locale in TARGET_LOCALES:
        text = whats_new[locale]
        existing_item = by_locale.get(locale)
        try:
            if existing_item is not None:
                payload = {
                    "data": {
                        "type": "betaBuildLocalizations",
                        "id": existing_item["id"],
                        "attributes": {"whatsNew": text},
                    }
                }
                response = release.asc_patch(f"betaBuildLocalizations/{existing_item['id']}", payload, token)
                results[locale] = ("updated", (response.get("data") or {}).get("id", existing_item["id"]))
                print(f"betaBuildLocalizations[{locale}]: updated")
            else:
                payload = {
                    "data": {
                        "type": "betaBuildLocalizations",
                        "attributes": {"locale": locale, "whatsNew": text},
                        "relationships": {
                            "build": {"data": {"type": "builds", "id": build_id}},
                        },
                    }
                }
                response = release.asc_post("betaBuildLocalizations", payload, token)
                loc_id = (response.get("data") or {}).get("id", "")
                results[locale] = ("created", loc_id)
                print(f"betaBuildLocalizations[{locale}]: created")
        except AscHttpError as error:
            if locale in SECONDARY_LOCALES and _is_secondary_locale_error(error):
                results[locale] = ("skipped", release.scrub(error))
                print(f"WARNING: App Store Connect rejected betaBuildLocalizations locale {locale!r}; "
                      f"continuing ({release.scrub(error)})")
            else:
                raise
    return results


def attach_build_to_group(token, group_id, build_id):
    attached_ids = set()
    for page in release.asc_pages(f"betaGroups/{group_id}/builds", {"fields[builds]": "version", "limit": 200}, token):
        for item in page.get("data") or []:
            attached_ids.add(item["id"])
    if build_id in attached_ids:
        print(f"betaGroups[{group_id}]: build {build_id} already attached")
        return False
    release.asc_post(
        f"betaGroups/{group_id}/relationships/builds",
        {"data": [{"type": "builds", "id": build_id}]},
        token,
    )
    print(f"betaGroups[{group_id}]: attached build {build_id}")
    return True


def fetch_beta_review_submission(token, build_id):
    try:
        response = release.asc_get(f"builds/{build_id}/betaAppReviewSubmission", {}, token)
        return response.get("data")
    except AscHttpError as error:
        if error.status_code == 404:
            return None
        raise


def submit_build_for_beta_review(token, build_id):
    existing = fetch_beta_review_submission(token, build_id)
    if existing is not None:
        state = (existing.get("attributes") or {}).get("betaReviewState", "")
        if state != "REJECTED":
            print(f"betaAppReviewSubmissions: existing submission found (state={state})")
            return existing
    payload = {
        "data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {
                "build": {"data": {"type": "builds", "id": build_id}},
            },
        }
    }
    response = release.asc_post("betaAppReviewSubmissions", payload, token)
    submission = response.get("data")
    if not submission:
        raise ReleaseError("App Store Connect returned an empty betaAppReviewSubmissions response")
    state = (submission.get("attributes") or {}).get("betaReviewState", "")
    print(f"betaAppReviewSubmissions: submitted (state={state})")
    return submission


def inspect_public_beta(token, app_id):
    print(f"App ID: {app_id}")

    builds = list_ios_builds(token, app_id)
    if builds:
        print(f"Latest iOS builds ({len(builds)} total, showing up to 10):")
        for build in builds[:10]:
            print(
                f"  - {build['marketingVersion']} ({build['version']}): "
                f"processingState={build['processingState']}, uploadedDate={build['uploadedDate']}"
            )
    else:
        print("Latest iOS builds: none")

    groups = list_beta_groups(token, app_id)
    if groups:
        print(f"Beta groups ({len(groups)}):")
        for group in groups:
            attrs = group.get("attributes") or {}
            print(
                f"  - {attrs.get('name')!r} (id={group['id']}): "
                f"isInternalGroup={attrs.get('isInternalGroup')}, "
                f"feedbackEnabled={attrs.get('feedbackEnabled')}, "
                f"publicLinkEnabled={attrs.get('publicLinkEnabled')}, "
                f"publicLinkLimitEnabled={attrs.get('publicLinkLimitEnabled')}, "
                f"publicLinkLimit={attrs.get('publicLinkLimit')}, "
                f"publicLink={attrs.get('publicLink') or '(none)'}"
            )
    else:
        print("Beta groups: none")

    localizations = list_beta_app_localizations(token, app_id)
    if localizations:
        print(f"Beta app localizations ({len(localizations)}):")
        for item in localizations:
            attrs = item.get("attributes") or {}
            desc_len = len((attrs.get("description") or "").strip())
            has_email = bool((attrs.get("feedbackEmail") or "").strip())
            print(
                f"  - {attrs.get('locale')}: descriptionChars={desc_len}, "
                f"feedbackEmailSet={has_email}"
            )
    else:
        print("Beta app localizations: none")

    detail = fetch_beta_app_review_detail(token, app_id)
    attrs = detail.get("attributes") or {}
    contact_complete = not review_contact_missing_fields(detail)
    notes_set = bool(isinstance(attrs.get("notes"), str) and attrs["notes"].strip())
    print(
        f"Beta App Review detail: contactComplete={contact_complete}, "
        f"demoAccountRequired={attrs.get('demoAccountRequired')}, "
        f"notesSet={notes_set}"
    )
    return {
        "app_id": app_id,
        "builds": builds,
        "groups": groups,
        "localizations": localizations,
        "contactComplete": contact_complete,
    }


def prepare_public_beta(token, app_id, *, group_name, feedback_email, public_link_limit=None, materials_path=MATERIALS_DOC):
    materials = load_external_materials(materials_path)
    email = validate_feedback_email(feedback_email)
    localizations = upsert_beta_app_localizations(token, app_id, materials["descriptions"], email)
    group = ensure_external_beta_group(token, app_id, group_name, public_link_limit=public_link_limit)
    review_detail = configure_beta_app_review_detail(token, app_id, materials["review_notes"])
    return {
        "app_id": app_id,
        "materials": materials,
        "localizations": localizations,
        "review_detail": review_detail,
        "group": group,
    }


def submit_public_beta(
    token,
    app_id,
    *,
    group_name,
    feedback_email,
    marketing_version,
    build_number=None,
    public_link_limit=None,
    wait_seconds=DEFAULT_WAIT_SECONDS,
    poll_interval=POLL_INTERVAL_SECONDS,
    sleep_fn=time.sleep,
    materials_path=MATERIALS_DOC,
):
    prepared = prepare_public_beta(
        token,
        app_id,
        group_name=group_name,
        feedback_email=feedback_email,
        public_link_limit=public_link_limit,
        materials_path=materials_path,
    )
    group = prepared["group"]
    materials = prepared["materials"]

    target_build = resolve_target_build(
        token,
        app_id,
        marketing_version,
        build_number=build_number,
        wait_seconds=wait_seconds,
        poll_interval=poll_interval,
        sleep_fn=sleep_fn,
    )
    upsert_beta_build_localizations(token, target_build["id"], materials["whats_new"])
    attach_build_to_group(token, group["id"], target_build["id"])
    submission = submit_build_for_beta_review(token, target_build["id"])

    if not ((group.get("attributes") or {}).get("publicLinkEnabled")):
        group = _patch_group_with_fallback(token, group, public_link_limit)

    group_attrs = group.get("attributes") or {}
    review_state = (submission.get("attributes") or {}).get("betaReviewState", "")
    public_link_enabled = bool(group_attrs.get("publicLinkEnabled"))
    public_link = group_attrs.get("publicLink")

    print(
        f"Public Beta summary: build={target_build['marketingVersion']} ({target_build['version']}), "
        f"betaReviewState={review_state}, "
        f"publicLinkEnabled={public_link_enabled}, "
        f"publicLink={public_link or '(pending Beta App Review approval)'}"
    )
    return {
        "build": target_build,
        "submission": submission,
        "betaReviewState": review_state,
        "group": group,
        "publicLinkEnabled": public_link_enabled,
        "publicLink": public_link,
    }


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--inspect", action="store_true",
                      help="read-only check of Clove builds, beta groups, localizations, and review contact status")
    mode.add_argument("--prepare", action="store_true",
                      help="idempotently configure betaAppLocalizations, betaAppReviewDetails, and external betaGroup without submitting a build")
    mode.add_argument("--submit", action="store_true",
                      help="run --prepare, attach a VALID build, set betaBuildLocalizations, and submit for Beta App Review")

    parser.add_argument("--config", help=f"TestFlight config (default: ${release.CONFIG_ENV_VAR}, "
                                         "then Config/TestFlight.local.json)")
    parser.add_argument("--group-name", default=DEFAULT_GROUP_NAME,
                        help=f"external TestFlight group name (default: {DEFAULT_GROUP_NAME!r})")
    parser.add_argument("--feedback-email",
                        help="feedback email written to betaAppLocalizations (required for --prepare and --submit unless feedbackEmail is in config)")
    parser.add_argument("--marketing-version", default=default_marketing_version(),
                        help="target marketing version (default: MARKETING_VERSION from project.yml)")
    parser.add_argument("--build",
                        help="target build number for --submit (default: highest VALID build for --marketing-version)")
    parser.add_argument("--public-link-limit", type=int,
                        help="optional tester limit for the public link (when omitted, publicLinkLimitEnabled=False)")
    parser.add_argument("--wait-seconds", type=int, default=DEFAULT_WAIT_SECONDS,
                        help=f"max seconds to wait if target build is PROCESSING in --submit (default: {DEFAULT_WAIT_SECONDS})")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    if args.public_link_limit is not None and args.public_link_limit < 1:
        raise ReleaseError("--public-link-limit must be a positive integer")
    if not re.fullmatch(r"\d+(\.\d+){0,2}", args.marketing_version):
        raise ReleaseError(f"Unusable --marketing-version {args.marketing_version!r}")

    config = asc_config(release.resolve_config_path(args.config))
    feedback_email = args.feedback_email or config.get("feedbackEmail")
    if (args.prepare or args.submit) and not feedback_email:
        raise ReleaseError("Missing --feedback-email (or feedbackEmail in config) for --prepare / --submit")

    token = release.jwt(config["apiKeyId"], config["issuerId"], config["apiKeyPath"])
    app_id = release.lookup_app(token, CLOVE)

    if args.inspect:
        inspect_public_beta(token, app_id)
    elif args.prepare:
        prepare_public_beta(
            token,
            app_id,
            group_name=args.group_name,
            feedback_email=feedback_email,
            public_link_limit=args.public_link_limit,
        )
    elif args.submit:
        submit_public_beta(
            token,
            app_id,
            group_name=args.group_name,
            feedback_email=feedback_email,
            marketing_version=args.marketing_version,
            build_number=args.build,
            public_link_limit=args.public_link_limit,
            wait_seconds=args.wait_seconds,
        )


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, OSError, ValueError, KeyError, urllib.error.URLError) as error:
        print("ERROR:", release.scrub(error), file=sys.stderr)
        sys.exit(1)
