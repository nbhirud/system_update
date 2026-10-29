#!/usr/bin/env python3
"""helper_mimeapps.py - edit freedesktop mimeapps.list files safely.

Specification: https://specifications.freedesktop.org/mime-apps-spec/latest-single

WHY PYTHON INSTEAD OF `xdg-mime default`
  * `xdg-mime` cannot remove entries, cannot touch [Removed Associations], and on KDE it
    shells out to `qtpaths` once per MIME type (noisy when that tool is missing).
  * A [Removed Associations] entry for an application in a higher-priority file
    BLACKLISTS it for that MIME type, so a plain "set default" can silently have no
    effect. This tool clears those entries as part of setting a default.
  * Editing happens in one pass with an atomic replace (write temp file, os.replace),
    so an interrupted run can never leave a half-written mimeapps.list.

SUBCOMMANDS (all options are named)
  set-default --desktop-id mpv.desktop --mime-types video/mp4 video/x-matroska ...
              [--file ~/.config/mimeapps.list] [--clean-file ~/.local/share/applications/mimeapps.list]
      Makes the application the ONLY default for each type in --file, removes it from
      [Removed Associations], and lists it in [Added Associations]. Entries for the same
      types are dropped from each --clean-file (the deprecated, lower-priority location).
  forget      --mime-types ... [--file ...]
      Removes the types from [Default Applications] in each file (used by a reset step).
  get-default --mime-type video/mp4 [--file ... --file ...]
      Prints the first default found (files in priority order), nothing if none.
  check       --desktop-id mpv.desktop --mime-types ... [--file ...]
      Exit 0 when every type resolves to the application; otherwise prints the failing
      types and exits 1.

Default file: $XDG_CONFIG_HOME/mimeapps.list (usually ~/.config/mimeapps.list).
"""
import argparse
import os
import sys
import tempfile

DEFAULTS, ADDED, REMOVED = "Default Applications", "Added Associations", "Removed Associations"


def default_file():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "mimeapps.list")


class MimeApps:
    """Minimal order-preserving parser: keeps comments, blank lines and unknown groups."""

    def __init__(self, path):
        self.path = path
        self.lines = []          # list of ("raw", text) | ("group", name) | ("kv", key, value)
        if os.path.exists(path):
            group = None
            with open(path, encoding="utf-8") as handle:
                for raw in handle.read().splitlines():
                    stripped = raw.strip()
                    if stripped.startswith("[") and stripped.endswith("]"):
                        group = stripped[1:-1]
                        self.lines.append(("group", group))
                    elif "=" in raw and not stripped.startswith("#") and group is not None:
                        key, value = raw.split("=", 1)
                        self.lines.append(("kv", group, key.strip(), value.strip()))
                    else:
                        self.lines.append(("raw", raw))

    # ---- queries -------------------------------------------------------------
    def get(self, group, key):
        for entry in self.lines:
            if entry[0] == "kv" and entry[1] == group and entry[2] == key:
                return [v for v in entry[3].split(";") if v]
        return []

    # ---- edits ---------------------------------------------------------------
    def _ensure_group(self, group):
        if not any(e[0] == "group" and e[1] == group for e in self.lines):
            if self.lines and self.lines[-1] != ("raw", ""):
                self.lines.append(("raw", ""))
            self.lines.append(("group", group))

    def set(self, group, key, values):
        """Set key to values (list). Empty list removes the key."""
        text = "".join(v + ";" for v in values)
        for i, entry in enumerate(self.lines):
            if entry[0] == "kv" and entry[1] == group and entry[2] == key:
                if values:
                    self.lines[i] = ("kv", group, key, text)
                else:
                    del self.lines[i]
                return
        if not values:
            return
        self._ensure_group(group)
        # insert after the last line belonging to the group
        insert_at, in_group = len(self.lines), False
        for i, entry in enumerate(self.lines):
            if entry[0] == "group":
                if in_group:
                    insert_at = i
                    break
                in_group = entry[1] == group
        else:
            insert_at = len(self.lines)
        while insert_at > 0 and self.lines[insert_at - 1] == ("raw", ""):
            insert_at -= 1
        self.lines.insert(insert_at, ("kv", group, key, text))

    def save(self):
        out = []
        for entry in self.lines:
            if entry[0] == "raw":
                out.append(entry[1])
            elif entry[0] == "group":
                out.append("[%s]" % entry[1])
            else:
                out.append("%s=%s" % (entry[2], entry[3]))
        text = "\n".join(out).rstrip("\n") + "\n"
        directory = os.path.dirname(self.path) or "."
        os.makedirs(directory, exist_ok=True)
        mode = 0o644
        if os.path.exists(self.path):
            mode = os.stat(self.path).st_mode & 0o777
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=".mimeapps.")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(text)
            os.chmod(tmp, mode)
            os.replace(tmp, self.path)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise


def cmd_set_default(args):
    main = MimeApps(args.file)
    for mime in args.mime_types:
        main.set(DEFAULTS, mime, [args.desktop_id])
        removed = [d for d in main.get(REMOVED, mime) if d != args.desktop_id]
        main.set(REMOVED, mime, removed)
        added = [args.desktop_id] + [d for d in main.get(ADDED, mime) if d != args.desktop_id]
        main.set(ADDED, mime, added)
    main.save()
    for other in args.clean_file or []:
        if os.path.exists(other) and os.path.abspath(other) != os.path.abspath(args.file):
            extra = MimeApps(other)
            for mime in args.mime_types:
                extra.set(DEFAULTS, mime, [])
                extra.set(REMOVED, mime, [d for d in extra.get(REMOVED, mime) if d != args.desktop_id])
            extra.save()
    return 0


def cmd_forget(args):
    for path in args.file or [default_file()]:
        if os.path.exists(path):
            doc = MimeApps(path)
            for mime in args.mime_types:
                doc.set(DEFAULTS, mime, [])
            doc.save()
    return 0


def resolve_default(mime, files):
    for path in files:
        values = MimeApps(path).get(DEFAULTS, mime)
        if values:
            return values[0]
    return ""


def cmd_get_default(args):
    value = resolve_default(args.mime_type, args.file or [default_file()])
    if value:
        print(value)
    return 0


def cmd_check(args):
    files = args.file or [default_file()]
    bad = []
    for mime in args.mime_types:
        blacklisted = any(args.desktop_id in MimeApps(p).get(REMOVED, mime) for p in files)
        if blacklisted or resolve_default(mime, files) != args.desktop_id:
            bad.append(mime)
    if bad:
        print("\n".join(bad))
        return 1
    return 0


def build_parser():
    parser = argparse.ArgumentParser(description="Edit freedesktop mimeapps.list files.")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("set-default")
    p.add_argument("--desktop-id", required=True)
    p.add_argument("--mime-types", nargs="+", required=True)
    p.add_argument("--file", default=default_file())
    p.add_argument("--clean-file", action="append")
    p.set_defaults(func=cmd_set_default)

    p = sub.add_parser("forget")
    p.add_argument("--mime-types", nargs="+", required=True)
    p.add_argument("--file", action="append")
    p.set_defaults(func=cmd_forget)

    p = sub.add_parser("get-default")
    p.add_argument("--mime-type", required=True)
    p.add_argument("--file", action="append")
    p.set_defaults(func=cmd_get_default)

    p = sub.add_parser("check")
    p.add_argument("--desktop-id", required=True)
    p.add_argument("--mime-types", nargs="+", required=True)
    p.add_argument("--file", action="append")
    p.set_defaults(func=cmd_check)
    return parser


if __name__ == "__main__":
    arguments = build_parser().parse_args()
    sys.exit(arguments.func(arguments))
