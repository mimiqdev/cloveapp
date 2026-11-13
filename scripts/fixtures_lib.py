"""Shared logic for the Clove test fixture tooling.

Used by ``scripts/fetch-fixtures``, ``scripts/make-fixture-sets`` and
``scripts/test_fixtures.py``. Standard library only, so it runs with the
system Python (``/usr/bin/python3``, currently 3.9 on macOS).

The fixture cache lives outside the repository, so parallel checkouts share
one download. Nothing here ever writes a binary file into the repository.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import urllib.parse
import urllib.request

CACHE_ENV = "CLOVE_FIXTURES_DIR"
DEFAULT_CACHE_DIR = "/Volumes/T7/Projects/.clove-fixtures"

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURES_DIR = os.path.join(REPO_ROOT, "fixtures")
MANIFEST_PATH = os.path.join(FIXTURES_DIR, "manifest.json")
GENERATED_PATH = os.path.join(FIXTURES_DIR, "generated.json")
SETS_PATH = os.path.join(FIXTURES_DIR, "sets.json")
XMP_DIR = os.path.join(FIXTURES_DIR, "xmp")

MANIFEST_REQUIRED = (
    "id",
    "format",
    "camera",
    "url",
    "bytes",
    "sha256",
    "source",
    "license",
    "notes",
)

USER_AGENT = "cloveapp-fixtures/1.0 (+https://github.com/mimiqdev/cloveapp)"
CHUNK_SIZE = 1 << 20
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class FixtureError(Exception):
    """A fixture problem with a message the user can act on."""


# --------------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------------


def cache_root(explicit=None):
    """Return the fixture cache root: explicit argument, env var, or default."""
    if explicit:
        return os.path.abspath(os.path.expanduser(explicit))
    from_env = os.environ.get(CACHE_ENV)
    if from_env:
        return os.path.abspath(os.path.expanduser(from_env))
    return DEFAULT_CACHE_DIR


def files_dir(cache):
    return os.path.join(cache, "files")


def generated_dir(cache):
    return os.path.join(cache, "generated")


def sets_dir(cache):
    return os.path.join(cache, "sets")


# --------------------------------------------------------------------------
# JSON loading
# --------------------------------------------------------------------------


def load_json(path):
    """Load a JSON file, reporting read and parse errors as FixtureError."""
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        raise FixtureError("no such file: %s" % path)
    except ValueError as error:
        raise FixtureError("%s is not valid JSON: %s" % (path, error))


# --------------------------------------------------------------------------
# Manifest
# --------------------------------------------------------------------------


def validate_manifest(document):
    """Validate a manifest document and return its entries.

    Raises FixtureError with a message naming the offending entry.
    """
    if not isinstance(document, dict):
        raise FixtureError("manifest must be a JSON object")
    files = document.get("files")
    if not isinstance(files, list) or not files:
        raise FixtureError("manifest must contain a non-empty 'files' list")

    seen = set()
    entries = []
    for index, entry in enumerate(files):
        where = "files[%d]" % index
        if not isinstance(entry, dict):
            raise FixtureError("%s must be an object" % where)
        for field in MANIFEST_REQUIRED:
            if field not in entry:
                raise FixtureError("%s is missing the required field %r" % (where, field))

        entry_id = entry["id"]
        if not isinstance(entry_id, str) or not SLUG_RE.match(entry_id):
            raise FixtureError(
                "%s has an invalid id %r (lowercase letters, digits and dashes only)"
                % (where, entry_id)
            )
        if entry_id in seen:
            raise FixtureError("%s repeats the id %r" % (where, entry_id))
        seen.add(entry_id)
        where = "file %r" % entry_id

        sha256 = entry["sha256"]
        if not isinstance(sha256, str) or not SHA256_RE.match(sha256):
            raise FixtureError(
                "%s has an invalid sha256 %r (expected 64 lowercase hex characters)"
                % (where, sha256)
            )

        size = entry["bytes"]
        if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
            raise FixtureError("%s has an invalid bytes value %r" % (where, size))

        url = entry["url"]
        if not isinstance(url, str) or not url.startswith(("https://", "http://")):
            raise FixtureError("%s has an invalid url %r" % (where, url))
        if any(character.isspace() for character in url):
            raise FixtureError("%s has a url containing whitespace; percent-encode it" % where)

        for field in ("format", "camera", "source", "license", "notes"):
            value = entry[field]
            if not isinstance(value, str) or not value.strip():
                raise FixtureError("%s has an empty %s" % (where, field))

        for field in ("licenseUrl", "attribution"):
            if field in entry and not isinstance(entry[field], str):
                raise FixtureError("%s has a non-string %s" % (where, field))

        entries.append(entry)
    return entries


def entries_by_id(entries):
    return {entry["id"]: entry for entry in entries}


def entry_filename(entry):
    """Return the cache file name for a manifest entry: ``<id><extension>``."""
    path = urllib.parse.urlsplit(entry["url"]).path
    extension = os.path.splitext(path)[1].lower()
    if not extension:
        raise FixtureError("file %r has no extension in its url" % entry["id"])
    return entry["id"] + extension


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(CHUNK_SIZE), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_file(path, entry):
    """Check a cached file against its manifest entry.

    Returns ``(ok, reason)``; ``reason`` is ``"ok"`` when the file matches.
    """
    if not os.path.isfile(path):
        return False, "missing"
    size = os.path.getsize(path)
    if size != entry["bytes"]:
        return False, "size %d, expected %d" % (size, entry["bytes"])
    digest = sha256_file(path)
    if digest != entry["sha256"]:
        return False, "sha256 %s, expected %s" % (digest[:12], entry["sha256"][:12])
    return True, "ok"


# --------------------------------------------------------------------------
# Downloading
# --------------------------------------------------------------------------


def http_download(url, destination, timeout=180):
    """Download ``url`` to ``destination`` (a temporary path)."""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        with open(destination, "wb") as handle:
            shutil.copyfileobj(response, handle, CHUNK_SIZE)


def fetch_entry(entry, destination, download=None, attempts=2):
    """Download and verify one entry, retrying a bad download.

    The bytes land in ``destination + ".part"`` first, so an interrupted run
    never leaves a partial file under the final name. Returns the number of
    downloads it took. Raises FixtureError when the checksum still mismatches.
    """
    download = download or http_download
    temporary = destination + ".part"
    reason = "unknown"
    for attempt in range(1, attempts + 1):
        if os.path.exists(temporary):
            os.remove(temporary)
        try:
            download(entry["url"], temporary)
        except Exception:
            if os.path.exists(temporary):
                os.remove(temporary)
            raise
        ok, reason = verify_file(temporary, entry)
        if ok:
            os.replace(temporary, destination)
            return attempt
        os.remove(temporary)
    raise FixtureError(
        "%s still does not match the manifest (%s) after %d download(s); nothing was kept"
        % (entry["id"], reason, attempts)
    )


def human_bytes(count):
    if count >= 1000 * 1000 * 1000:
        return "%.2f GB" % (count / 1e9)
    if count >= 1000 * 1000:
        return "%.1f MB" % (count / 1e6)
    if count >= 1000:
        return "%.0f KB" % (count / 1e3)
    return "%d B" % count


def sync_files(entries, directory, download=None, log=print):
    """Make ``directory`` hold every entry, verified, downloading what is missing.

    Returns ``(summary, failures)``. A file whose checksum does not match is
    deleted and downloaded again; a file that still does not match is reported
    as a failure and left out of the cache.
    """
    os.makedirs(directory, exist_ok=True)
    summary = {"cached": 0, "downloaded": 0, "repaired": 0, "failed": 0, "bytes": 0}
    failures = []

    for entry in entries:
        name = entry_filename(entry)
        destination = os.path.join(directory, name)
        ok, reason = verify_file(destination, entry)

        if ok:
            summary["cached"] += 1
            log("cached    %-38s %9s  %s" % (entry["id"], human_bytes(entry["bytes"]), name))
            continue

        if os.path.exists(destination):
            log(
                "repair    %-38s %9s  %s (%s)"
                % (entry["id"], human_bytes(entry["bytes"]), name, reason)
            )
            os.remove(destination)
            outcome = "repaired"
        else:
            log("fetch     %-38s %9s  %s" % (entry["id"], human_bytes(entry["bytes"]), name))
            outcome = "downloaded"

        try:
            fetch_entry(entry, destination, download=download)
        except Exception as error:
            summary["failed"] += 1
            failures.append((entry["id"], str(error)))
            log("FAILED    %-38s %s" % (entry["id"], error))
            continue

        summary[outcome] += 1
        summary["bytes"] += entry["bytes"]

    return summary, failures


# --------------------------------------------------------------------------
# Generated files
# --------------------------------------------------------------------------


def validate_recipes(document):
    """Validate ``fixtures/generated.json`` and return its recipes."""
    if not isinstance(document, dict):
        raise FixtureError("generated.json must be a JSON object")
    recipes = document.get("recipes")
    if not isinstance(recipes, list) or not recipes:
        raise FixtureError("generated.json must contain a non-empty 'recipes' list")

    seen = set()
    validated = []
    for index, recipe in enumerate(recipes):
        where = "recipes[%d]" % index
        if not isinstance(recipe, dict):
            raise FixtureError("%s must be an object" % where)
        for field in ("id", "format", "extension", "tool", "args", "notes"):
            if field not in recipe:
                raise FixtureError("%s is missing the required field %r" % (where, field))
        recipe_id = recipe["id"]
        if not isinstance(recipe_id, str) or not SLUG_RE.match(recipe_id):
            raise FixtureError("%s has an invalid id %r" % (where, recipe_id))
        if recipe_id in seen:
            raise FixtureError("%s repeats the id %r" % (where, recipe_id))
        seen.add(recipe_id)
        where = "recipe %r" % recipe_id
        if not isinstance(recipe["args"], list) or not all(
            isinstance(argument, str) for argument in recipe["args"]
        ):
            raise FixtureError("%s needs a list of string args" % where)
        if not recipe["extension"].startswith("."):
            raise FixtureError("%s needs an extension such as '.jpg'" % where)
        validated.append(recipe)
    return validated


def recipes_by_id(recipes):
    return {recipe["id"]: recipe for recipe in recipes}


def generate_file(recipe, source, destination):
    """Run a recipe (``sips``) to build a generated file from a cached download."""
    executable = shutil.which(recipe["tool"])
    if executable is None:
        raise FixtureError(
            "recipe %r needs %r, which is not on PATH; generated fixtures are "
            "built on macOS" % (recipe["id"], recipe["tool"])
        )
    command = [executable] + list(recipe["args"]) + [source, "--out", destination]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        raise FixtureError(
            "recipe %r failed for %s: %s"
            % (
                recipe["id"],
                os.path.basename(source),
                result.stderr.decode("utf-8", "replace").strip(),
            )
        )
    if not os.path.isfile(destination) or os.path.getsize(destination) == 0:
        raise FixtureError(
            "recipe %r produced no output for %s"
            % (recipe["id"], os.path.basename(source))
        )


# --------------------------------------------------------------------------
# Sets
# --------------------------------------------------------------------------


def _expand_item(item, where):
    """Expand an optional repeat count into unique, four-digit indexed paths."""
    if not isinstance(item, dict):
        raise FixtureError("%s must be an object" % where)
    repeat = item.get("repeat", 1)
    if not isinstance(repeat, int) or isinstance(repeat, bool) or repeat <= 0:
        raise FixtureError("%s needs a positive integer 'repeat'" % where)
    if repeat == 1:
        return [item]
    destination = item.get("to")
    if not isinstance(destination, str) or "{index}" not in destination:
        raise FixtureError("%s with 'repeat' needs '{index}' in 'to'" % where)
    expanded = []
    for index in range(1, repeat + 1):
        copy = dict(item)
        copy["to"] = destination.replace("{index}", "%04d" % index)
        del copy["repeat"]
        if "from" in item:
            copy["hardlink"] = True
        expanded.append(copy)
    return expanded


def _check_relative(path, where):
    if not isinstance(path, str) or not path.strip():
        raise FixtureError("%s has an empty path" % where)
    if path.startswith("/") or os.path.isabs(path):
        raise FixtureError("%s uses an absolute path %r" % (where, path))
    parts = path.replace(os.sep, "/").split("/")
    if any(part in ("..", "") for part in parts[:-1]) or parts[-1] in ("..", ".", ""):
        raise FixtureError("%s escapes the set folder: %r" % (where, path))


def resolve_sets(document, entries, recipes, files_directory, xmp_directory, generated_directory):
    """Validate ``fixtures/sets.json`` and resolve every entry to a source.

    Returns a list of ``{"name": str, "entries": [...]}`` where each entry has
    ``to``, ``kind`` (``copy``, ``text``, ``bytes`` or ``generate``) and its source.
    """
    if not isinstance(document, dict):
        raise FixtureError("sets.json must be a JSON object")
    sets = document.get("sets")
    if not isinstance(sets, list) or not sets:
        raise FixtureError("sets.json must contain a non-empty 'sets' list")

    known_files = entries_by_id(entries)
    known_recipes = recipes_by_id(recipes)
    seen_names = set()
    resolved = []

    for index, spec in enumerate(sets):
        where = "sets[%d]" % index
        if not isinstance(spec, dict):
            raise FixtureError("%s must be an object" % where)
        name = spec.get("name")
        if not isinstance(name, str) or not SLUG_RE.match(name):
            raise FixtureError("%s has an invalid name %r" % (where, name))
        if name in seen_names:
            raise FixtureError("%s repeats the set name %r" % (where, name))
        seen_names.add(name)
        where = "set %r" % name

        items = spec.get("entries")
        if not isinstance(items, list) or not items:
            raise FixtureError("%s has no entries" % where)

        expanded_items = []
        for item_index, item in enumerate(items):
            expanded_items.extend(_expand_item(item, "%s entries[%d]" % (where, item_index)))

        destinations = set()
        resolved_entries = []
        for item_index, item in enumerate(expanded_items):
            item_where = "%s entries[%d]" % (where, item_index)
            if not isinstance(item, dict):
                raise FixtureError("%s must be an object" % item_where)
            destination = item.get("to")
            _check_relative(destination, item_where)
            if destination in destinations:
                raise FixtureError("%s repeats the path %r" % (item_where, destination))
            destinations.add(destination)

            has_file = "from" in item
            has_xmp = "fromXmp" in item
            has_text = "text" in item
            has_hex = "hex" in item
            if sum((has_file, has_xmp, has_text, has_hex)) != 1:
                raise FixtureError(
                    "%s needs exactly one of 'from', 'fromXmp', 'text' or 'hex'"
                    % item_where
                )
            if "recipe" in item and not has_file:
                raise FixtureError("%s uses 'recipe' without 'from'" % item_where)

            if has_file:
                source_id = item["from"]
                if source_id not in known_files:
                    raise FixtureError(
                        "%s references the unknown manifest id %r" % (item_where, source_id)
                    )
                source_entry = known_files[source_id]
                source_path = os.path.join(files_directory, entry_filename(source_entry))
                if "recipe" in item:
                    recipe_id = item["recipe"]
                    if recipe_id not in known_recipes:
                        raise FixtureError(
                            "%s references the unknown recipe %r" % (item_where, recipe_id)
                        )
                    recipe = known_recipes[recipe_id]
                    resolved_entries.append(
                        {
                            "to": destination,
                            "kind": "generate",
                            "path": source_path,
                            "sourceID": source_id,
                            "sourceSHA256": source_entry["sha256"],
                            "hardlink": item.get("hardlink", False),
                            "recipe": recipe,
                            "cache_path": os.path.join(
                                generated_directory,
                                "%s--%s%s" % (recipe["id"], source_id, recipe["extension"]),
                            ),
                        }
                    )
                else:
                    resolved_entries.append(
                        {
                            "to": destination,
                            "kind": "copy",
                            "path": source_path,
                            "sourceID": source_id,
                            "sourceSHA256": source_entry["sha256"],
                            "hardlink": item.get("hardlink", False),
                        }
                    )
            elif has_xmp:
                sidecar = item["fromXmp"]
                _check_relative(sidecar, item_where)
                source_path = os.path.join(xmp_directory, sidecar)
                if not os.path.isfile(source_path):
                    raise FixtureError(
                        "%s references the missing sidecar %r" % (item_where, sidecar)
                    )
                resolved_entries.append(
                    {"to": destination, "kind": "copy", "path": source_path}
                )
            else:
                if has_text:
                    if not isinstance(item["text"], str):
                        raise FixtureError("%s has a non-string 'text'" % item_where)
                    resolved_entries.append(
                        {"to": destination, "kind": "text", "text": item["text"]}
                    )
                else:
                    payload = item["hex"]
                    if not isinstance(payload, str) or len(payload) % 2 or not payload:
                        raise FixtureError(
                            "%s needs an even-length hex string" % item_where
                        )
                    try:
                        data = bytes.fromhex(payload)
                    except ValueError:
                        raise FixtureError(
                            "%s has a 'hex' value that is not hexadecimal" % item_where
                        )
                    resolved_entries.append(
                        {"to": destination, "kind": "bytes", "data": data}
                    )

        identity = spec.get("identity", False)
        if not isinstance(identity, bool):
            raise FixtureError("%s has a non-boolean 'identity'" % where)
        resolved_spec = {"name": name, "entries": resolved_entries, "identity": None}
        if identity:
            canonical = json.dumps(spec, sort_keys=True, separators=(",", ":")).encode("utf-8")
            sources = {}
            for entry in resolved_entries:
                if "sourceID" in entry:
                    sources[entry["sourceID"]] = entry["sourceSHA256"]
            resolved_spec["identity"] = {
                "definitionSHA256": hashlib.sha256(canonical).hexdigest(),
                "sources": sources,
            }
        resolved.append(resolved_spec)

    return resolved


def build_sets(resolved_sets, directory, copy=None, generate=None, log=print):
    """Recreate every set under ``directory``; returns ``[(name, count), ...]``.

    Each set folder is deleted first, so the result is the same on every run
    and never carries a file from an older definition.
    """
    copy = copy or shutil.copyfile
    generate = generate or generate_file
    os.makedirs(directory, exist_ok=True)
    report = []

    for spec in resolved_sets:
        target = os.path.join(directory, spec["name"])
        if os.path.isdir(target) and not os.path.islink(target):
            shutil.rmtree(target)
        elif os.path.exists(target):
            os.remove(target)
        os.makedirs(target)

        for entry in spec["entries"]:
            destination = os.path.join(target, entry["to"])
            if os.path.commonpath([os.path.abspath(target), os.path.abspath(destination)]) != os.path.abspath(target):
                raise FixtureError(
                    "set %r would write outside its folder: %r" % (spec["name"], entry["to"])
                )
            parent = os.path.dirname(destination)
            if parent:
                os.makedirs(parent, exist_ok=True)

            if entry["kind"] == "text":
                with open(destination, "w", encoding="utf-8", newline="\n") as handle:
                    handle.write(entry["text"])
            elif entry["kind"] == "bytes":
                with open(destination, "wb") as handle:
                    handle.write(entry["data"])
            elif entry["kind"] == "copy":
                if not os.path.isfile(entry["path"]):
                    raise FixtureError(
                        "missing source for %r: %s (run scripts/fetch-fixtures first)"
                        % (entry["to"], entry["path"])
                    )
                if entry.get("hardlink"):
                    try:
                        os.link(entry["path"], destination)
                    except OSError:
                        copy(entry["path"], destination)
                else:
                    copy(entry["path"], destination)
            elif entry["kind"] == "generate":
                cached = entry["cache_path"]
                if not os.path.isfile(cached) or os.path.getsize(cached) == 0:
                    if not os.path.isfile(entry["path"]):
                        raise FixtureError(
                            "missing source for %r: %s (run scripts/fetch-fixtures first)"
                            % (entry["to"], entry["path"])
                        )
                    os.makedirs(os.path.dirname(cached), exist_ok=True)
                    log("generating %s from %s" % (os.path.basename(cached), entry["path"]))
                    generate(entry["recipe"], entry["path"], cached)
                if entry.get("hardlink"):
                    try:
                        os.link(cached, destination)
                    except OSError:
                        copy(cached, destination)
                else:
                    copy(cached, destination)
            else:
                raise FixtureError("unknown entry kind %r" % entry["kind"])

        if spec.get("identity"):
            document = {
                "schemaVersion": 1,
                "set": spec["name"],
                "fileCount": len(spec["entries"]),
                "definitionSHA256": spec["identity"]["definitionSHA256"],
                "sources": spec["identity"]["sources"],
            }
            identity_path = os.path.join(target, ".clove-fixture.json")
            with open(identity_path, "w", encoding="utf-8", newline="\n") as handle:
                json.dump(document, handle, sort_keys=True, indent=2)
                handle.write("\n")

        report.append((spec["name"], len(spec["entries"])))

    return report


def set_file_list(directory, root):
    """Return the sorted relative file paths under ``root`` inside ``directory``."""
    paths = []
    for current, _directories, filenames in os.walk(root):
        for filename in filenames:
            full = os.path.join(current, filename)
            paths.append(os.path.relpath(full, directory).replace(os.sep, "/"))
    return sorted(paths)
