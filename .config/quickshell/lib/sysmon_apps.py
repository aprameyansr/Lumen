"""Attribute Linux process accounting to desktop applications."""

from collections import defaultdict
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import signal
import sys
import time

from sysmon import command, process_drm_clients, read
from sysmon_models import AI_ICON, display_name, identify_model

PROC = Path("/proc")
UID = os.getuid()
PAGE_KIB = os.sysconf("SC_PAGE_SIZE") // 1024
CPU_COUNT = os.cpu_count() or 1
TICKS = os.sysconf("SC_CLK_TCK")
SYSTEM = "@system"
DICTATION = "@dictation"
WRAPPERS = {"sh", "bash", "env", "flatpak", "python", "python3", "electron", "java", "node", "wine"}


@dataclass
class Task:
    parent: int
    start: int
    ticks: int
    rss: int
    uid: int
    virtual: int = 0
    name: str = ""


def task(pid):
    path = PROC / str(pid)
    try:
        label, raw_fields = read(path / "stat").rsplit(")", 1)
        fields = raw_fields.split()
        if fields[0] in ("Z", "X"):
            return None
        return Task(int(fields[1]), int(fields[19]), int(fields[11]) + int(fields[12]),
                    max(0, int(fields[21])) * PAGE_KIB, path.stat().st_uid,
                    int(fields[20]), label.split("(", 1)[1])
    except (IndexError, ValueError, OSError, UnicodeError):
        return None


def normalize(value):
    return value.lower().removesuffix(".desktop").removesuffix(".appimage")


def dictation_process(args, directory):
    if str(directory / "dictated.py") in args[1:]:
        return "Dictation"
    if args[0] == str(directory / "whisper" / "whisper-server"):
        model = identify_model(args)
        return display_name(*model) if model else "Whisper"
    return None


def identify(tasks, entries, windows, dictate_dir=None, dictate_engine=""):
    apps = {entry["id"]: entry for entry in entries}
    aliases = defaultdict(set)
    binaries = defaultdict(set)
    for app in entries:
        for name in (app["id"], app.get("startup", "")):
            if name:
                aliases[normalize(name)].add(app["id"])
        args = app.get("command", [])
        # A launcher shared by multiple apps is never enough to identify one.
        if args and Path(args[0]).name not in WRAPPERS:
            binaries[normalize(Path(args[0]).name)].add(app["id"])
    owners = {}
    own_windows = set()
    window_executables = defaultdict(set)
    scopes = {}
    model_runners = {}
    ollama_services = set()
    dictation_label = "Parakeet" if "parakeet" in dictate_engine.lower() else "Dictation"

    def match(index, name):
        options = index.get(normalize(name), ())
        return next(iter(options)) if len(options) == 1 else None

    for window in windows:
        pid = window.get("pid")
        if pid not in tasks or tasks[pid].uid != UID:
            continue
        identity = window.get("initialClass") or window.get("class")
        if not identity:
            continue
        key = match(aliases, identity) or match(aliases, window.get("class", "")) or "window:" + normalize(identity)
        apps.setdefault(key, {"id": key, "name": identity, "icon": identity})
        owners[pid] = key
        own_windows.add(pid)
        try:
            executable = os.readlink(PROC / str(pid) / "exe")
            if Path(executable).name not in WRAPPERS:
                window_executables[executable].add(key)
        except OSError:
            pass

    for pid, info in tasks.items():
        if info.uid != UID:
            continue
        path = PROC / str(pid)
        try:
            args = (path / "cmdline").read_bytes().decode(errors="replace").rstrip("\0").split("\0")
        except OSError:
            args = [""]
        if Path(args[0]).name.lower() == "ollama" and args[1:2] == ["serve"]:
            ollama_services.add(pid)
        service = dictation_process(args, dictate_dir) if dictate_dir else None
        if service:
            owners[pid] = DICTATION
            if service != "Dictation":
                dictation_label = service
        else:
            runner = identify_model(args)
            if runner:
                model_runners[pid] = runner
                owners[pid] = "@model:" + json.dumps(runner, separators=(",", ":"))
        for line in read(path / "cgroup").splitlines():
            scope = next((name for name in reversed(line.split('/'))
                          if name.startswith("app-") and name.endswith((".scope", ".service"))), "")
            if scope:
                scopes[pid] = scope
                break
        if pid in owners:
            continue
        try:
            executable = os.readlink(path / "exe")
        except OSError:
            continue
        options = window_executables.get(executable, ())
        # The exact executable also catches reparented helpers with the app binary.
        owners[pid] = (next(iter(options)) if len(options) == 1 else
                       match(binaries, Path(executable).name))
        if owners[pid] is None:
            del owners[pid]

    if DICTATION in owners.values():
        apps[DICTATION] = {"id": DICTATION, "name": dictation_label, "icon": AI_ICON}
    for pid, (runtime, model) in model_runners.items():
        key = owners[pid]
        apps[key] = {"id": key, "name": display_name(runtime, model), "icon": AI_ICON}
        parent = tasks[pid].parent
        if runtime == "Ollama" and parent in ollama_services and tasks[parent].start <= tasks[pid].start:
            owners[parent] = key

    scoped_owners = defaultdict(set)
    for pid, key in owners.items():
        if pid in scopes and apps[key].get("icon") != AI_ICON:
            scoped_owners[scopes[pid]].add(key)
    scope_fallback = {
        pid: next(iter(scoped_owners[scope]))
        for pid, scope in scopes.items() if len(scoped_owners[scope]) == 1
    }

    def owner(pid):
        chain = []
        current = pid
        while current in tasks and current not in owners:
            chain.append(current)
            parent = tasks[current].parent
            if parent == current or parent in chain or (parent in tasks and tasks[parent].start > tasks[current].start):
                break
            current = parent
        key = owners.get(current, SYSTEM)
        for item in reversed(chain):
            if key == SYSTEM:
                key = scope_fallback.get(item, SYSTEM)
            owners[item] = key
        return key

    for pid in tasks:
        owner(pid)
    return owners, apps, own_windows


def snapshot():
    tasks = {}
    clients = {}
    for path in PROC.iterdir():
        if not path.name.isdecimal():
            continue
        pid = int(path.name)
        info = task(pid)
        if not info:
            continue
        tasks[pid] = info
        for device, client, counters in process_drm_clients(path):
            key = (device, client)
            if key not in clients:
                clients[key] = (set(), counters)
            clients[key][0].add(pid)
    return time.clock_gettime(time.CLOCK_BOOTTIME), tasks, clients


def memory(pid, info):
    if info.rss == 0 and info.virtual == 0:
        return 0, False
    for line in read(PROC / str(pid) / "smaps_rollup").splitlines():
        if line.startswith("Pss:"):
            return int(line.split()[1]), False
    return info.rss, True


def drm_usage(before, after, elapsed, tasks, previous, owners):
    engines = defaultdict(float)
    for (device, client), (pids, counters) in after.items():
        old_pids, prior = before.get((device, client), (set(), {}))
        shared = {owners[pid] for pid in pids & old_pids
                  if pid in previous and pid in tasks and previous[pid].start == tasks[pid].start}
        if not shared:
            continue
        owner = next(iter(shared)) if len(shared) == 1 else SYSTEM
        for key, value in counters.items():
            if key.startswith("cycles-"):
                engine = key.removeprefix("cycles-")
                clock = "total-cycles-" + engine
                if clock not in prior or clock not in counters:
                    continue
                denominator = counters[clock] - prior[clock]
            elif key.startswith("engine-") and not key.startswith("engine-capacity-"):
                engine = key.removeprefix("engine-")
                if "cycles-" + engine in counters and "total-cycles-" + engine in counters:
                    continue
                denominator = elapsed * 1e9
            else:
                continue
            if denominator > 0 and key in prior:
                capacity = max(1, counters.get("engine-capacity-" + engine, 1))
                engines[owner, device, engine] += max(0, value - prior[key]) / (denominator * capacity)
    usage = defaultdict(float)
    for (owner, _, _), value in engines.items():
        usage[owner] = min(100, max(usage[owner], value * 100))
    return usage


def nvidia_usage(owners):
    totals = defaultdict(float)
    for line in command("nvidia-smi", "pmon", "-c", "1", "-s", "u").splitlines():
        columns = line.split()
        if len(columns) > 3 and columns[1].isdigit() and columns[3].isdigit():
            totals[owners.get(int(columns[1]), SYSTEM), columns[0]] += int(columns[3])
    usage = defaultdict(float)
    for (owner, _), value in totals.items():
        usage[owner] = min(100, max(usage[owner], value))
    return usage


def protected_pids(tasks):
    # Never signal the sampler or its launcher chain.
    protected = {1}
    pid = os.getpid()
    while pid in tasks and pid not in protected:
        protected.add(pid)
        pid = tasks[pid].parent
    return protected


def processor_percent(info, prior, before_time, elapsed):
    if elapsed <= 0:
        return 0.0
    if prior and prior.start == info.start:
        ticks = max(0, info.ticks - prior.ticks)
    else:
        ticks = info.ticks if info.start >= int(before_time * TICKS) else 0
    return ticks * 100 / (TICKS * elapsed * CPU_COUNT)


def application_owners(tasks, entries, dictate_dir, dictate_engine):
    windows = json.loads(command("hyprctl", "-j", "clients") or "[]")
    return identify(tasks, entries, windows, dictate_dir, dictate_engine)


def sample(entries, nvidia, dictate_dir=None, dictate_engine=""):
    before_time, previous, before = snapshot()
    time.sleep(0.65)
    now, tasks, after = snapshot()
    elapsed = now - before_time
    owners, apps, window_pids = application_owners(tasks, entries, dictate_dir, dictate_engine)
    gpu = drm_usage(before, after, elapsed, tasks, previous, owners)
    for owner, utilization in (nvidia_usage(owners).items() if nvidia else ()):
        gpu[owner] = max(gpu.get(owner, 0), utilization)

    protected = protected_pids(tasks)

    rows = {}
    for pid, info in tasks.items():
        key = owners[pid]
        if key not in rows:
            row = dict(apps.get(key, {"id": SYSTEM, "name": "System processes", "icon": ""}))
            row.pop("command", None)
            row.pop("startup", None)
            row.update(memory=0, estimated=False, cpu=0, gpu=gpu.get(key) if nvidia else
                       gpu.get(key, 0) if before or after else None, count=0, members=[], targets=[], roots=[])
            rows[key] = row
        row = rows[key]
        kib, estimated = memory(pid, info)
        row["memory"] += kib
        row["estimated"] |= estimated
        row["cpu"] += processor_percent(info, previous.get(pid), before_time, elapsed)
        row["count"] += 1
        row["members"].append(f"{pid}:{info.start}")
        if key != SYSTEM and info.uid == UID and pid not in protected:
            identity = [pid, info.start]
            row["targets"].append(identity)
            if owners.get(info.parent) != key or pid in window_pids:
                row["roots"].append(identity)
    return sorted(rows.values(), key=lambda row: (row["id"] == SYSTEM, row["name"].casefold()))


def login_uid_range():
    limits = {"UID_MIN": 1000, "UID_MAX": 60000}
    for line in read(Path("/etc/login.defs")).splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[0] in limits and fields[1].isdigit():
            limits[fields[0]] = int(fields[1])
    return limits["UID_MIN"], limits["UID_MAX"]


def process_rows(before, after, nvidia, uid_range, app_owners):
    before_time, previous, earlier_drm = before
    now, tasks, later_drm = after
    elapsed = now - before_time
    owners = {pid: str(pid) for pid in tasks}
    gpu = drm_usage(earlier_drm, later_drm, elapsed, tasks, previous, owners)
    for key, utilization in (nvidia_usage(owners).items() if nvidia else ()):
        gpu[key] = max(gpu.get(key, 0), utilization)

    minimum, maximum = uid_range
    protected = protected_pids(tasks)
    rows = []
    for pid, info in tasks.items():
        owner = info.uid
        if owner == 0:
            # A user's non-dumpable process can have a root-owned proc directory.
            status = read(PROC / str(pid) / "status")
            uid = re.search(r"^Uid:\s+(\d+)\s+(\d+)", status, re.M)
            owner = int(uid[1]) if uid and int(uid[2]) != 0 else 0
        if not owner or (owner != UID and not minimum <= owner <= maximum):
            continue
        key = str(pid)
        targets = [[pid, info.start]] if info.uid == UID and pid not in protected else []
        kib, estimated = memory(pid, info)
        rows.append({
            "id": f"{pid}:{info.start}", "name": info.name, "pid": pid,
            "appGroup": app_owners.get(pid, SYSTEM),
            "memory": kib, "estimated": estimated,
            "cpu": processor_percent(info, previous.get(pid), before_time, elapsed),
            "gpu": gpu.get(key) if nvidia else gpu.get(key, 0) if earlier_drm or later_drm else None,
            "targets": targets, "roots": targets,
        })
    return rows


def stream_processes(nvidia, entries, dictate_dir, dictate_engine):
    limits = login_uid_range()
    before = snapshot()
    while True:
        time.sleep(max(0, before[0] + 1 - time.clock_gettime(time.CLOCK_BOOTTIME)))
        after = snapshot()
        owners, _, _ = application_owners(after[1], entries, dictate_dir, dictate_engine)
        print(json.dumps(process_rows(before, after, nvidia, limits, owners)), flush=True)
        before = after


def send_signal(mode, identities):
    if mode not in ("terminate", "kill"):
        raise ValueError("Unknown app action")
    sent = skipped = 0
    for pid, start in identities:
        if type(pid) is not int or pid < 2 or pid in (os.getpid(), os.getppid()):
            skipped += 1
            continue
        try:
            fd = os.pidfd_open(pid)
        except OSError:
            skipped += 1
            continue
        try:
            current = task(pid)
            if not current or current.start != start or current.uid != UID:
                skipped += 1
                continue
            signal.pidfd_send_signal(fd, signal.SIGTERM if mode == "terminate" else signal.SIGKILL)
            sent += 1
        except OSError:
            skipped += 1
        finally:
            os.close(fd)
    return {"sent": sent, "skipped": skipped}


if __name__ == "__main__":
    mode, payload, *options = sys.argv[1:]
    if mode == "processes":
        entries, directory, engine = (options + ["[]", "", ""])[:3]
        stream_processes(payload == "nvidia", json.loads(entries),
                         Path(directory) if directory else None, engine)
        sys.exit(0)
    data = json.loads(payload)
    if mode == "sample":
        vendor, directory, engine = (options + ["", "", ""])[:3]
        result = sample(data, vendor == "nvidia", Path(directory) if directory else None, engine)
    else:
        result = send_signal(mode, data)
    print(json.dumps(result))
