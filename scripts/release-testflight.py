#!/usr/bin/python3
"""Archive, sign locally, validate, and optionally upload Clove or Clove Lab to TestFlight.

The App Store Connect key, the distribution certificate, and the App Store
profiles stay outside the repository and are referenced from a gitignored
config (see Config/TestFlight.local.json.example). A temporary keychain holds
the Apple Distribution identity during the build; it is removed and the user
keychain search list restored on every exit path. The default validates the
exported IPA with App Store Connect; --upload publishes it, refusing to run
from a dirty worktree.

    mise run release -- --app lab
    mise run release -- --config ~/.config/apple/clove-testflight.json --app clove
    mise run release -- --app lab --upload
"""

import argparse
import hashlib
import json
import os
import plistlib
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parent.parent
PROJECT = "Clove.xcodeproj"
CONFIG_ENV_VAR = "CLOVE_TESTFLIGHT_CONFIG"
DEFAULT_CONFIG = ROOT / "Config" / "TestFlight.local.json"
DEFAULT_BETA_GROUP = "Clove Lab Internal"
ARTIFACTS = ROOT / ".build" / "testflight"
ASC_HOST = "https://api.appstoreconnect.apple.com/v1/"


class App(NamedTuple):
    key: str
    scheme: str
    target: str
    product: str
    bundle_id: str
    display_name: str


APPS = {
    "clove": App("clove", "Clove", "Clove", "Clove", "com.mimiqdev.clove", "Clove"),
    "lab": App("lab", "CloveLab", "CloveLab", "CloveLab", "com.mimiqdev.clove.lab", "Clove Lab"),
}


class ReleaseError(Exception):
    pass


_SECRETS = []


def register_secret(value):
    """Remember a config value that must never reach stdout or an error message."""
    if value and value not in _SECRETS:
        _SECRETS.append(value)


def scrub(text):
    result = str(text)
    for value in sorted(_SECRETS, key=len, reverse=True):
        result = result.replace(value, "[redacted]")
    return result


def command(argv, *, log=None):
    """Run one command in the checkout. Never echo more than its program name."""
    program = str(argv[0])
    if log is None:
        result = subprocess.run([str(argument) for argument in argv],
                                cwd=ROOT, text=True, capture_output=True)
        if result.returncode:
            raise ReleaseError(f"{program} failed ({result.returncode}): {result.stderr.strip()[-800:]}")
        return result.stdout
    log = Path(log)
    try:
        with open(log, "w") as output:
            result = subprocess.run([str(argument) for argument in argv],
                                    cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    except OSError as error:
        raise ReleaseError(f"Cannot run {program} with log {log}: {error}") from error
    if result.returncode:
        lines = log.read_text(errors="replace").splitlines() if log.exists() else []
        raise ReleaseError(f"{program} failed ({result.returncode}); log: {log}\n"
                           + "\n".join(scrub(line) for line in lines[-20:]))
    return ""


def generate_project():
    script = ROOT / "scripts" / "generate-xcodeproj.sh"
    if not script.is_file():
        raise ReleaseError("Missing scripts/generate-xcodeproj.sh")
    result = subprocess.run([str(script)], cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        raise ReleaseError(f"xcodegen failed ({result.returncode}): "
                           f"{scrub(result.stderr.strip()[-800:])}")
    print(f"Generated {PROJECT}")


def working_tree_changes():
    return command(["git", "status", "--porcelain", "--untracked-files=normal"]).strip()


def ensure_clean_tree():
    changes = working_tree_changes()
    if changes:
        raise ReleaseError("Refusing to upload from a dirty worktree:\n" + changes)


SECTION_HEADER = re.compile(r"^Build settings for action .* and target (.+):$")
SETTING_LINE = re.compile(r"^\s+([A-Za-z0-9_]+) = (.*)$")


def parse_build_settings(output, target):
    """Pick one target's settings out of `xcodebuild -showBuildSettings` output."""
    settings = {}
    current = None
    for line in output.splitlines():
        header = SECTION_HEADER.match(line)
        if header:
            current = header.group(1)
            continue
        if current != target:
            continue
        match = SETTING_LINE.match(line)
        if match:
            settings[match.group(1)] = match.group(2).strip()
    return settings


def app_build_settings(app):
    output = command(["xcodebuild", "-project", PROJECT, "-scheme", app.scheme,
                      "-configuration", "Release", "-showBuildSettings"])
    settings = parse_build_settings(output, app.target)
    if not settings:
        raise ReleaseError(f"No Xcode build settings for target {app.target}")
    bundle_id = settings.get("PRODUCT_BUNDLE_IDENTIFIER")
    if bundle_id != app.bundle_id:
        raise ReleaseError(f"{app.target} builds {bundle_id!r}, expected {app.bundle_id!r}")
    marketing = settings.get("MARKETING_VERSION", "")
    if not re.fullmatch(r"\d+(\.\d+){0,2}", marketing):
        raise ReleaseError(f"Unusable MARKETING_VERSION {marketing!r}")
    return marketing


def jwt(key_id, issuer_id, key_path):
    result = subprocess.run(["xcrun", "altool", "--generate-jwt", "--apiKey", key_id,
                             "--apiIssuer", issuer_id, "--p8-file-path", str(key_path)],
                            cwd=ROOT, text=True, capture_output=True)
    # altool writes the token to stderr on some Xcode versions. Never print it.
    match = re.search(r"eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+",
                      result.stdout + "\n" + result.stderr)
    if result.returncode or not match:
        raise ReleaseError("altool could not generate an App Store Connect API token")
    register_secret(match.group(0))
    return match.group(0)


def asc_json(url, token):
    """GET one App Store Connect JSON resource, refusing non-HTTPS URLs."""
    if urllib.parse.urlsplit(url).scheme != "https":
        raise ReleaseError("Refusing non-HTTPS App Store Connect URL: " + url)
    request = urllib.request.Request(  # noqa: S310 -- scheme checked above
        url, headers={"Authorization": "Bearer " + token, "Accept": "application/json"})
    try:
        # The scheme is checked above, so urlopen only sees the documented API
        # host or a pagination link Apple returned over HTTPS.
        with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310
            return json.load(response)
    except urllib.error.HTTPError as error:
        try:
            details = [(item.get("code"), item.get("title")) for item in json.load(error).get("errors", [])]
        except (ValueError, OSError):
            details = []
        raise ReleaseError(f"App Store Connect {url}: HTTP {error.code}, {details}") from error
    except (ValueError, OSError) as error:
        raise ReleaseError(f"App Store Connect {url}: unreadable response ({error})") from error


def asc_get(path, params, token):
    return asc_json(ASC_HOST + path + "?" + urllib.parse.urlencode(params, doseq=True), token)


def asc_pages(path, params, token):
    """Yield App Store Connect pages, following Apple's pagination links."""
    page = asc_get(path, params, token)
    while True:
        yield page
        url = (page.get("links") or {}).get("next")
        if not url:
            return
        page = asc_json(url, token)


def lookup_app(token, app):
    data = asc_get("apps", {"filter[bundleId]": app.bundle_id,
                            "fields[apps]": "bundleId,name", "limit": 10}, token)
    # The API filter matches a prefix, so com.mimiqdev.clove also returns
    # com.mimiqdev.clove.lab. Keep the exact record only.
    records = [record for record in data.get("data") or []
               if (record.get("attributes") or {}).get("bundleId") == app.bundle_id]
    if len(records) != 1:
        raise ReleaseError(f"Expected exactly one App Store Connect app for "
                           f"{app.bundle_id}, found {len(records)}")
    name = (records[0].get("attributes") or {}).get("name", app.display_name)
    print(f"App Store Connect app: {name} ({app.bundle_id})")
    return records[0]["id"]


def check_beta_group(token, app_id, group_name):
    """Fail before archiving when the internal TestFlight group is missing."""
    params = {"filter[app]": app_id, "limit": 200,
              "fields[betaGroups]": "name,isInternalGroup,hasAccessToAllBuilds"}
    for page in asc_pages("betaGroups", params, token):
        for group in page.get("data") or []:
            attributes = group.get("attributes") or {}
            if attributes.get("name") != group_name:
                continue
            note = ""
            if attributes.get("isInternalGroup") and attributes.get("hasAccessToAllBuilds"):
                note = ", internal, access to all builds"
            print(f"TestFlight group {group_name!r}: found{note}")
            return group["id"]
    raise ReleaseError(f"TestFlight group {group_name!r} does not exist for this app; "
                       "create it in App Store Connect or set betaGroup in the config")


def visible_builds(token, app_id):
    """Every uploaded iOS build as (marketing version, build number)."""
    params = {"filter[app]": app_id, "sort": "-uploadedDate", "limit": 200,
              "fields[builds]": "version,preReleaseVersion", "include": "preReleaseVersion",
              "fields[preReleaseVersions]": "version,platform"}
    builds = []
    for page in asc_pages("builds", params, token):
        versions = {item["id"]: (item.get("attributes") or {}).get("version")
                    for item in page.get("included") or []
                    if item.get("type") == "preReleaseVersions"
                    and (item.get("attributes") or {}).get("platform") == "IOS"}
        for build in page.get("data") or []:
            release = ((build.get("relationships") or {}).get("preReleaseVersion") or {}).get("data")
            if not release or release.get("id") not in versions:
                continue
            builds.append((versions[release["id"]], (build.get("attributes") or {}).get("version", "")))
    return builds


def next_build_number(visible, marketing_version, now=None):
    """UTC yymmddhh, strictly greater than every build for this marketing version."""
    # Use UTC so daylight-saving or local timezone changes cannot move backwards.
    timestamp = int((now or datetime.now(timezone.utc)).astimezone(timezone.utc).strftime("%y%m%d%H"))
    for version, number in visible:
        if version != marketing_version:
            continue
        if not number.isdecimal():
            raise ReleaseError(f"Non-integer TestFlight build number {number!r}; refusing to guess")
        if int(number) >= timestamp:
            raise ReleaseError(
                f"UTC build {timestamp} is not greater than visible {marketing_version} ({number}); "
                "wait until a later UTC hour"
            )
    return timestamp


def lookup_build_number(token, app_id, marketing_version):
    builds = visible_builds(token, app_id)
    number = next_build_number(builds, marketing_version)
    chosen = [build for version, build in builds if version == marketing_version]
    print(f"Build number: {number} for {marketing_version} (visible: {chosen})")
    return number


def profile_details(path, app):
    raw = subprocess.run(["security", "cms", "-D", "-i", str(path)], capture_output=True)
    if raw.returncode:
        raise ReleaseError("Cannot decode App Store provisioning profile")
    profile = plistlib.loads(raw.stdout)
    entitlements = profile.get("Entitlements") or {}
    if (entitlements.get("get-task-allow") is not False
            or "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices")):
        raise ReleaseError("Profile is not an App Store distribution profile")
    team = profile["TeamIdentifier"][0]
    if entitlements.get("application-identifier") != team + "." + app.bundle_id:
        raise ReleaseError("Profile does not match " + app.bundle_id)
    return profile, team


def read_json_config(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise ReleaseError(f"Cannot read {path}: {error}") from error


def resolve_config_path(explicit, environ=None):
    """--config, then $CLOVE_TESTFLIGHT_CONFIG, then Config/TestFlight.local.json."""
    if explicit:
        return Path(explicit).expanduser()
    environ = os.environ if environ is None else environ
    configured = environ.get(CONFIG_ENV_VAR, "").strip()
    if configured:
        return Path(configured).expanduser()
    return DEFAULT_CONFIG


def signing_file(value, label, *, secret):
    path = Path(value).expanduser().resolve()
    if ROOT == path or ROOT in path.parents:
        raise ReleaseError(f"{label} must live outside the repository: {path}")
    if not path.is_file():
        raise ReleaseError(f"Missing signing file for {label}: {path}")
    if secret and path.stat().st_mode & 0o077:
        raise ReleaseError(f"Restrict {label} to your user: chmod 600 {path}")
    return path


def release_config(path, app):
    path = Path(path)
    if not path.is_file():
        raise ReleaseError(f"Missing {path}; copy Config/TestFlight.local.json.example "
                           "and fill it in, or pass --config")
    if path.stat().st_mode & 0o077:
        raise ReleaseError(f"Restrict {path} to your user: chmod 600 {path}")
    config = read_json_config(path)
    if not isinstance(config, dict):
        raise ReleaseError(f"Incomplete TestFlight config: {path}")
    profiles = config.get("appStoreProfiles")
    if not isinstance(profiles, dict):
        raise ReleaseError(f"Incomplete TestFlight config: {path} has no appStoreProfiles")
    for key in APPS:
        if not isinstance(profiles.get(key), str) or not profiles[key]:
            raise ReleaseError(f"Incomplete TestFlight config: {path} has no appStoreProfiles[{key!r}]")
    for key in ("apiKeyId", "issuerId", "apiKeyPath",
                "distributionP12Path", "distributionP12PasswordFile"):
        if not isinstance(config.get(key), str) or not config[key]:
            raise ReleaseError(f"Incomplete TestFlight config: {path} needs {key}")
    group = config.get("betaGroup", DEFAULT_BETA_GROUP)
    if not isinstance(group, str) or not group.strip():
        raise ReleaseError(f"Incomplete TestFlight config: {path} has an empty betaGroup")
    config["betaGroup"] = group.strip()
    config["apiKeyPath"] = signing_file(config["apiKeyPath"], "apiKeyPath", secret=True)
    config["distributionP12Path"] = signing_file(config["distributionP12Path"],
                                                 "distributionP12Path", secret=True)
    config["distributionP12PasswordFile"] = signing_file(config["distributionP12PasswordFile"],
                                                         "distributionP12PasswordFile", secret=True)
    config["profilePath"] = signing_file(profiles[app.key],
                                         f"appStoreProfiles[{app.key!r}]", secret=False)
    register_secret(config["apiKeyId"])
    register_secret(config["issuerId"])
    config["p12Password"] = config["distributionP12PasswordFile"].read_text().rstrip("\r\n")
    if not config["p12Password"]:
        raise ReleaseError("Empty distribution .p12 password file")
    register_secret(config["p12Password"])
    return config


@contextmanager
def local_signing(app, profile_path, p12_path, p12_password, output_dir):
    """Yield (profile_name, team, certificate hash); restore keychain and profile on exit."""
    profile, team = profile_details(profile_path, app)
    keychain = output_dir / "signing.keychain-db"
    password = secrets.token_urlsafe(36)
    search_list = shlex.split(command(["security", "list-keychains", "-d", "user"]))
    profile_dest = (Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
                    / (profile["UUID"] + ".mobileprovision"))
    installed = False
    created = False
    try:
        command(["security", "create-keychain", "-p", password, str(keychain)])
        created = True
        command(["security", "unlock-keychain", "-p", password, str(keychain)])
        command(["security", "set-keychain-settings", "-lut", "21600", str(keychain)])
        command(["security", "import", str(p12_path), "-k", str(keychain), "-P", p12_password,
                 "-T", "/usr/bin/codesign"])
        command(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
                 "-s", "-k", password, str(keychain)])
        identities = command(["security", "find-identity", "-v", "-p", "codesigning", str(keychain)])
        # find-identity prints SHA-1 digests; this matches the imported identity
        # against the profile's certificates, it does not protect data.
        expected = {hashlib.new("sha1", bytes(cert), usedforsecurity=False).hexdigest().upper()
                    for cert in profile["DeveloperCertificates"]}
        matches = [match.group(1) for line in identities.splitlines()
                   if (match := re.search(r"\b([A-F0-9]{40})\b.*Apple Distribution:", line))
                   and match.group(1) in expected and f"({team})" in line]
        if len(matches) != 1:
            raise ReleaseError("Imported Apple Distribution identity does not match the profile")
        profile_dest.parent.mkdir(parents=True, exist_ok=True)
        if profile_dest.exists():
            if profile_dest.read_bytes() != Path(profile_path).read_bytes():
                raise ReleaseError("Another profile already uses this UUID")
        else:
            shutil.copyfile(profile_path, profile_dest)
            profile_dest.chmod(0o600)
            installed = True
        command(["security", "list-keychains", "-d", "user", "-s", str(keychain), *search_list])
        yield profile["Name"], team, matches[0]
    finally:
        if installed:
            try:
                profile_dest.unlink()
            except OSError as error:
                print("WARNING: could not remove temporary profile:", error, file=sys.stderr)
        try:
            command(["security", "list-keychains", "-d", "user", "-s", *search_list])
        except ReleaseError as error:
            print("WARNING: could not restore keychain search list:", scrub(error), file=sys.stderr)
        if created:
            try:
                command(["security", "delete-keychain", str(keychain)])
            except ReleaseError as error:
                print("WARNING: could not delete temporary keychain:", scrub(error), file=sys.stderr)


def archive(app, number, marketing, output_dir, cert_hash, team, profile_name):
    archive_path = output_dir / f"{app.scheme}.xcarchive"
    # Command-line signing overrides apply to every target, including SPM
    # package products, which reject a manual provisioning profile specifier.
    # Archive unsigned and let -exportArchive apply the Apple Distribution
    # certificate and the App Store profile from ExportOptions.
    command(["xcodebuild", "-project", PROJECT, "-scheme", app.scheme,
             "-configuration", "Release", "-destination", "generic/platform=iOS",
             "-derivedDataPath", str(output_dir / "DerivedData"),
             "-archivePath", str(archive_path),
             "CODE_SIGNING_ALLOWED=NO",
             "CURRENT_PROJECT_VERSION=" + str(number),
             "MARKETING_VERSION=" + marketing,
             "archive"], log=output_dir / "archive.log")
    options = {"method": "app-store-connect", "destination": "export", "signingStyle": "manual",
               "signingCertificate": cert_hash, "teamID": team,
               "provisioningProfiles": {app.bundle_id: profile_name},
               "manageAppVersionAndBuildNumber": False}
    options_path = output_dir / "ExportOptions.plist"
    options_path.write_bytes(plistlib.dumps(options))
    command(["xcodebuild", "-exportArchive", "-archivePath", str(archive_path),
             "-exportPath", str(output_dir / "export"),
             "-exportOptionsPlist", str(options_path)], log=output_dir / "export.log")
    ipa = output_dir / "export" / f"{app.product}.ipa"
    if not ipa.is_file():
        raise ReleaseError(f"Xcode export finished without {app.product}.ipa")
    return ipa


def verify_ipa(ipa, app, marketing_version, build_number, team):
    with zipfile.ZipFile(ipa) as archive_file:
        info_path = f"Payload/{app.product}.app/Info.plist"
        try:
            info = plistlib.loads(archive_file.read(info_path))
        except KeyError:
            raise ReleaseError(f"IPA has no {info_path}; was {app.product}.app archived?") from None
        if (info.get("CFBundleIdentifier") != app.bundle_id
                or info.get("CFBundleShortVersionString") != marketing_version
                or info.get("CFBundleVersion") != str(build_number)
                or info.get("ITSAppUsesNonExemptEncryption") is not False):
            raise ReleaseError("Exported IPA has unexpected ID, version, build, or compliance declaration")
        with tempfile.TemporaryDirectory(prefix="clove-ipa-check-") as temp:
            archive_file.extractall(temp)
            app_path = Path(temp) / "Payload" / f"{app.product}.app"
            command(["codesign", "--verify", "--deep", "--strict", str(app_path)])
            signature = subprocess.run(["codesign", "-dvv", str(app_path)],
                                       capture_output=True, text=True)
            if (signature.returncode or "Authority=Apple Distribution:" not in signature.stderr
                    or f"TeamIdentifier={team}" not in signature.stderr):
                raise ReleaseError("IPA was not signed locally by the expected Apple Distribution team")
            embedded, embedded_team = profile_details(app_path / "embedded.mobileprovision", app)
            if embedded_team != team:
                raise ReleaseError("IPA embeds a profile from another team")
    print(f"IPA verified: {app.bundle_id} {marketing_version} ({build_number}), "
          "Apple Distribution, export compliance declared")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--app", required=True, choices=sorted(APPS),
                        help="app to release: clove or lab")
    parser.add_argument("--config", help=f"TestFlight config (default: ${CONFIG_ENV_VAR}, "
                                         "then Config/TestFlight.local.json)")
    parser.add_argument("--upload", action="store_true",
                        help="upload after local signing and Apple validation")
    args = parser.parse_args(argv)
    app = APPS[args.app]
    config = release_config(resolve_config_path(args.config), app)
    if args.upload:
        ensure_clean_tree()
    generate_project()
    marketing = app_build_settings(app)
    token = jwt(config["apiKeyId"], config["issuerId"], config["apiKeyPath"])
    app_id = lookup_app(token, app)
    if app.key == "lab":
        check_beta_group(token, app_id, config["betaGroup"])
    number = lookup_build_number(token, app_id, marketing)
    output_dir = ARTIFACTS / app.key
    shutil.rmtree(output_dir, ignore_errors=True)
    output_dir.mkdir(parents=True)
    print("Artifacts and logs:", output_dir)
    ipa = None
    with local_signing(app, config["profilePath"], config["distributionP12Path"],
                       config["p12Password"], output_dir) as (profile_name, team, cert_hash):
        ipa = archive(app, number, marketing, output_dir, cert_hash, team, profile_name)
        verify_ipa(ipa, app, marketing, number, team)
    auth = ["--api-key", config["apiKeyId"], "--api-issuer", config["issuerId"],
            "--p8-file-path", str(config["apiKeyPath"])]
    command(["xcrun", "altool", "--validate-app", "-f", str(ipa), "-t", "ios", *auth],
            log=output_dir / "validate.log")
    print("Apple validation passed. IPA:", ipa)
    if args.upload:
        command(["xcrun", "altool", "--upload-app", "-f", str(ipa), "-t", "ios", *auth],
                log=output_dir / "upload.log")
        text = (output_dir / "upload.log").read_text(errors="replace")
        delivery = re.search(r"Delivery UUID:\s*([\w-]+)", text)
        print("Upload accepted; delivery ID:", delivery.group(1) if delivery else "see upload.log")
        print("Processing and TestFlight availability are asynchronous; check App Store Connect.")
    else:
        print("No upload requested. Pass --upload to publish a build.")


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, OSError, ValueError, KeyError, urllib.error.URLError) as error:
        print("ERROR:", scrub(error), file=sys.stderr)
        sys.exit(1)
