"""Private, boot-local copies of files held by the pill."""

import ctypes
from functools import cache
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
from urllib.parse import unquote, urlsplit
from tempfile import TemporaryDirectory


try:
    import gi

    gi.require_version("Gtk", "4.0")
    from gi.repository import Gio, GLib, Gtk
except (ImportError, ValueError):
    Gtk = None


@cache
def desktop_icon_theme():
    theme = Gtk.IconTheme.new()
    schema = Gio.SettingsSchemaSource.get_default()
    if schema and schema.lookup("org.gnome.desktop.interface", True):
        theme.set_theme_name(Gio.Settings.new("org.gnome.desktop.interface").get_string("icon-theme"))
    return theme


def file_icon(file):
    if Gtk is None:
        return ""
    names = []
    try:
        info = Gio.File.new_for_path(str(file)).query_info("standard::icon", Gio.FileQueryInfoFlags.NONE, None)
        icon = info.get_icon()
        if isinstance(icon, Gio.ThemedIcon):
            names = icon.get_names()
    except GLib.Error:
        pass
    theme = desktop_icon_theme()
    for name in [*names, "text-x-generic"]:
        if not theme.has_icon(name):
            continue
        paintable = theme.lookup_icon(name, None, 48, 1, Gtk.TextDirection.NONE, 0)
        asset = paintable.get_file()
        if asset and asset.is_native():
            return asset.get_uri()
    return ""


TEMP_ROOT = Path("/tmp")


def is_private_directory(path):
    info = path.lstat()
    return stat.S_ISDIR(info.st_mode) and info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700


def shelf_directory():
    directory = TEMP_ROOT / "lumen-shelf"
    directory.mkdir(mode=0o700, exist_ok=True)
    if not is_private_directory(directory):
        raise OSError("The temporary shelf directory is not private")
    return directory


def publish_directory(source, destination):
    # Linux renameat2 publishes a complete directory without replacing an existing one.
    rename = ctypes.CDLL(None, use_errno=True).renameat2
    rename.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint)
    rename.restype = ctypes.c_int
    at_fdcwd, rename_noreplace = -100, 1
    if rename(at_fdcwd, os.fsencode(source), at_fdcwd, os.fsencode(destination), rename_noreplace):
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), destination)


def publish(source, directory, name, is_folder=False):
    number = 1
    stem, extension = os.path.splitext(name)
    limit = os.pathconf(directory, "PC_NAME_MAX")
    while True:
        suffix = f" ({number}){extension}"
        base = stem
        while base and len(os.fsencode(base + suffix)) > limit:
            base = base[:-1]
        if len(os.fsencode(suffix)) > limit:
            base, suffix = name, f" ({number})"
            while len(os.fsencode(base + suffix)) > limit:
                base = base[:-1]
        destination = directory / (name if number == 1 else base + suffix)
        try:
            if is_folder:
                publish_directory(source, destination)
            else:
                os.link(source, destination, follow_symlinks=False)
            return
        except FileExistsError:
            number += 1


def migrate_previous_shelf(directory):
    old = TEMP_ROOT / f"lumen-file-shelf-{os.getuid()}"
    try:
        if not is_private_directory(old):
            return
    except FileNotFoundError:
        return

    for slot in sorted(old.iterdir(), key=lambda entry: entry.lstat().st_mtime_ns):
        if not re.fullmatch(r"[a-f0-9]{32}", slot.name) or not is_private_directory(slot):
            continue
        for file in slot.iterdir():
            if not stat.S_ISREG(file.lstat().st_mode):
                continue
            publish(file, directory, file.name)
            file.unlink()
        if not any(slot.iterdir()):
            slot.rmdir()
    if not any(old.iterdir()):
        old.rmdir()


def entries(directory):
    results = []
    for file in directory.iterdir():
        try:
            info = file.lstat()
        except FileNotFoundError:
            continue
        is_folder = stat.S_ISDIR(info.st_mode)
        if is_folder or stat.S_ISREG(info.st_mode):
            results.append({
                "id": f"{info.st_ino}:{file.name}", "name": file.name, "url": file.as_uri(),
                "size": info.st_size, "directory": is_folder, "added": info.st_ctime_ns, "icon": file_icon(file),
            })
    results.sort(key=lambda item: item["added"], reverse=True)
    return results


def source_path(url):
    source_url = urlsplit(url)
    if source_url.scheme != "file" or source_url.netloc.lower() not in ("", "localhost"):
        raise OSError("Only local files can be stored")
    source = Path(unquote(source_url.path))
    if not source.is_absolute() or not source.name:
        raise OSError("Only local files can be stored")
    return source


def inspect(urls):
    files = folders = 0
    for url in urls:
        try:
            source = source_path(url)
            if source.is_dir():
                folders += 1
            elif source.is_file():
                files += 1
        except (OSError, ValueError):
            continue
    return {"files": files, "folders": folders}


def store(directory, url):
    source = source_path(url)
    resolved = source.resolve(strict=True)
    if resolved.is_relative_to(directory):
        raise OSError("This file is already on the shelf")
    is_folder = resolved.is_dir()
    if not is_folder and not resolved.is_file():
        raise OSError("Only files and folders can be stored")
    if is_folder and directory.is_relative_to(resolved):
        raise OSError("This folder contains the shelf")
    with TemporaryDirectory(prefix=".lumen-shelf-staging-", dir=directory.parent) as staging:
        copy = Path(staging) / "item"
        if is_folder:
            shutil.copytree(resolved, copy, symlinks=True)
        else:
            shutil.copy2(resolved, copy)
        publish(copy, directory, source.name, is_folder)
    return is_folder


def remove(directory, identifier):
    inode, separator, name = identifier.partition(":")
    if not separator or not inode.isdecimal() or not name or name in {".", ".."} or "/" in name:
        return
    file = directory / name
    try:
        info = file.lstat()
        if str(info.st_ino) != inode:
            return
        if stat.S_ISDIR(info.st_mode):
            shutil.rmtree(file)
        elif stat.S_ISREG(info.st_mode):
            file.unlink()
    except FileNotFoundError:
        pass


def main(action, values):
    if action == "inspect":
        return inspect(values)
    directory = shelf_directory()
    files = folders = 0
    errors = []
    try:
        migrate_previous_shelf(directory)
    except OSError as error:
        errors.append(error.strerror or str(error))
    if action == "store":
        for url in values:
            try:
                if store(directory, url):
                    folders += 1
                else:
                    files += 1
            except (OSError, ValueError, RuntimeError) as error:
                errors.append(error.strerror if isinstance(error, OSError) and error.strerror else str(error))
    elif action == "remove":
        for identifier in values:
            try:
                remove(directory, identifier)
            except OSError as error:
                errors.append(error.strerror or str(error))
    return {"entries": entries(directory), "stored": files + folders,
            "files": files, "folders": folders, "errors": errors}


if __name__ == "__main__":
    mode, *arguments = sys.argv[1:]
    try:
        print(json.dumps(main(mode, arguments)))
    except OSError as error:
        print(json.dumps({"errors": [error.strerror or str(error)], "stored": 0}))
