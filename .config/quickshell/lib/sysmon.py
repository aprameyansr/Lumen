"""Read Linux hardware data for the pill's system monitor."""

import csv
import json
import os
from pathlib import Path
import re
import socket
import struct
import subprocess
import sys
import time

SYS = Path("/sys")
VENDORS = {"0x8086": "Intel Corporation", "0x1002": "AMD", "0x10de": "NVIDIA"}


def read(path):
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def command(*args):
    try:
        return subprocess.run(
            args, capture_output=True, text=True, check=True, timeout=2,
            env=dict(os.environ, LC_ALL="C"),
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def json_command(*args):
    return json.loads(command(*args) or "{}")


def number(value):
    match = re.match(r"-?\d+(?:\.\d+)?", value.strip())
    return float(match[0]) if match else None


def scaled(value, divisor):
    return value / divisor if value is not None else None


def first_number(paths):
    for path in paths:
        value = number(read(path))
        if value is not None:
            return value
    return None


def cpu_properties():
    fields = {
        item["field"].rstrip(":"): item["data"]
        for item in json_command("lscpu", "--json").get("lscpu", [])
    }
    topology = [
        line.split(",") for line in command("lscpu", "-p=CORE,SOCKET").splitlines()
        if not line.startswith("#")
    ]
    cores = {tuple(row) for row in topology if len(row) == 2 and all(x.isdigit() for x in row)}
    return {
        "name": fields.get("Model name"), "maxMhz": number(fields.get("CPU max MHz") or ""),
        "logical": fields.get("CPU(s)"), "physical": len(cores) or None,
        "sockets": fields.get("Socket(s)"), "virtualization": fields.get("Virtualization"),
        "architecture": fields.get("Architecture") or os.uname().machine,
    }


def memory_properties():
    # udev caches the firmware's SMBIOS memory records for unprivileged readers.
    output = command("udevadm", "info", "--query=property", "--path=/sys/devices/virtual/dmi/id")
    fields = dict(line.split("=", 1) for line in output.splitlines() if "=" in line)
    slots = int(fields.get("MEMORY_ARRAY_NUM_DEVICES", "0"))
    if not slots:
        return {}
    devices = [
        {key: fields.get(f"MEMORY_DEVICE_{slot}_{key}", "") for key in (
            "PRESENT", "SIZE", "CONFIGURED_SPEED_MTS", "SPEED_MTS", "FORM_FACTOR", "TYPE", "TYPE_DETAIL",
        )}
        for slot in range(slots)
    ]
    populated = [
        device for device in devices
        if device["PRESENT"] == "1" or (number(device["SIZE"]) or 0) > 0
    ]
    speeds = sorted({int(speed) for device in populated if (
        speed := number(device["CONFIGURED_SPEED_MTS"]) or number(device["SPEED_MTS"])
    )})

    def labels(key):
        return " · ".join(sorted({
            device[key] for device in populated if device[key]
            and device[key].lower() not in {"unknown", "out of spec", "not specified"}
        }))

    known = len(populated) + sum(device["PRESENT"] == "0" for device in devices)
    return {
        "slots": slots, "populated": len(populated) if known == slots else None,
        "speed": " / ".join(map(str, speeds)),
        "formFactor": labels("FORM_FACTOR"), "type": labels("TYPE"), "typeDetail": labels("TYPE_DETAIL"),
    }


def cpu_sensor():
    drivers = {"coretemp", "k10temp", "zenpower", "k8temp", "cpu_thermal", "acpitz"}
    candidates = []
    for sensor in sorted((SYS / "class/hwmon").glob("hwmon*")):
        if read(sensor / "name") not in drivers:
            continue
        for probe in sorted(sensor.glob("temp*_input")):
            label = read(probe.with_name(probe.name.replace("_input", "_label")))
            rank = {"Tdie": 0, "Package id 0": 1, "Tctl": 2}.get(label, 3)
            candidates.append((rank, str(probe)))
    return min(candidates)[1] if candidates else ""


def nvidia_query(fields, pci=""):
    device = ["-i", pci] if pci else []
    reply = command("nvidia-smi", *device, "--query-gpu=" + ",".join(fields),
                    "--format=csv,noheader,nounits")
    row = next(csv.reader(reply.splitlines(), skipinitialspace=True), [])
    return dict(zip(fields, row))


def detect():
    gpu = {}
    nvidia = nvidia_query(["pci.bus_id", "name"])
    if nvidia.get("pci.bus_id"):
        # NVML prints an eight-digit PCI domain. Sysfs uses four.
        domain, bus, address = nvidia["pci.bus_id"].lower().split(":")
        pci = f"{int(domain, 16):04x}:{bus}:{address}"
        gpu = {"vendor": "nvidia", "pci": pci, "path": str(SYS / "bus/pci/devices" / pci),
               "name": nvidia.get("name")}
    else:
        cards = sorted((SYS / "class/drm").glob("card[0-9]*"))
        for vendor, vendor_id, drivers in (("amd", "0x1002", {"amdgpu"}),
                                           ("intel", "0x8086", {"i915", "xe"})):
            for card in cards:
                device = card / "device"
                driver = (device / "driver").resolve().name
                if read(device / "vendor") != vendor_id or driver not in drivers:
                    continue
                gpu = {"vendor": vendor, "pci": device.resolve().name, "path": str(device),
                       "card": str(card)}
                break
            if gpu:
                break
    return {"cpu": cpu_properties(), "sensor": cpu_sensor(), "gpu": gpu,
            "memory": memory_properties(), "pageSize": os.sysconf("SC_PAGE_SIZE")}


def pci_name(device):
    fields = {}
    output = command("lspci", "-vmm", "-s", device.resolve().name)
    for line in output.splitlines():
        key, sep, value = line.partition(":")
        if sep:
            fields[key] = value.strip()
    return fields


def pcie_link(device):
    speed = number(read(device / "current_link_speed"))
    width = number(read(device / "current_link_width"))
    return f"PCIe ×{width:g} · {speed:g} GT/s" if speed and width else None


def process_drm_clients(process):
    prefixes = ("engine-", "cycles-", "total-cycles-", "maxfreq-")
    try:
        for fd in (process / "fd").iterdir():
            try:
                if not os.readlink(fd).startswith("/dev/dri/"):
                    continue
            except OSError:
                continue
            fields = dict(
                line[4:].split(":", 1) for line in
                read(process / "fdinfo" / fd.name).splitlines()
                if line.startswith("drm-") and ":" in line
            )
            client = fields.get("client-id", "").strip()
            device = fields.get("pdev", "").strip()
            if not client:
                continue
            if not device:
                device = os.readlink(fd)
            counters = {}
            for key, raw in fields.items():
                if key.startswith(prefixes):
                    value = number(raw)
                    if value is not None:
                        counters[key] = value
            yield device, client, counters
    except OSError:
        return


def drm_clients(pci):
    clients = {}
    for process in Path("/proc").glob("[0-9]*"):
        for device, client, counters in process_drm_clients(process):
            if device == pci:
                clients.setdefault(client, counters)
    return clients


def gpu_sample(vendor, path, pci, card_path, details):
    device = Path(path)
    card = Path(card_path or path)
    hwmons = sorted((device / "hwmon").glob("hwmon*"))
    data = {}
    if vendor == "nvidia":
        fields = ["utilization.gpu", "temperature.gpu", "memory.used", "memory.total"]
        if details:
            fields += ["clocks.gr", "clocks.mem", "power.draw", "power.max_limit",
                       "pcie.link.gen.current", "pcie.link.width.current"]
        values = {key: number(value) for key, value in nvidia_query(fields, pci).items()}
        data = {"usage": values.get("utilization.gpu"), "temp": values.get("temperature.gpu"),
                "vramUsed": scaled(values.get("memory.used"), 1024),
                "vramTotal": scaled(values.get("memory.total"), 1024)}
        if details:
            gen = values.get("pcie.link.gen.current")
            width = values.get("pcie.link.width.current")
            data.update(coreMhz=values.get("clocks.gr"), memoryMhz=values.get("clocks.mem"),
                        watts=values.get("power.draw"), cap=values.get("power.max_limit"),
                        link=f"PCIe {gen:g}.0 ×{width:g}" if gen and width else pcie_link(device))
    else:
        driver = (device / "driver").resolve().name
        temperature = "temp2_input" if driver == "xe" else "temp1_input"
        data["temp"] = scaled(first_number(h / temperature for h in hwmons), 1000)
        if vendor == "intel":
            data["clients"] = drm_clients(pci)
            data["time"] = time.monotonic_ns()
        else:
            data.update(usage=first_number([device / "gpu_busy_percent"]),
                        vramUsed=scaled(first_number([device / "mem_info_vram_used"]), 2**30),
                        vramTotal=scaled(first_number([device / "mem_info_vram_total"]), 2**30))
        if details:
            data.update(
                coreMhz=first_number([card / "gt_act_freq_mhz"]
                                     + sorted(card.glob("gt/gt*/freq0/act_freq"))
                                     + sorted(card.glob("gt/gt*/rps_act_freq_mhz"))
                                     + [h / "freq1_input" for h in hwmons]),
                memoryMhz=scaled(first_number(h / "freq2_input" for h in hwmons), 1e6),
                watts=scaled(first_number(h / key for key in ("power1_average", "power1_input")
                                          for h in hwmons), 1e6),
                cap=scaled(first_number(h / "power1_cap_max" for h in hwmons), 1e6),
                link=pcie_link(device),
            )
            if vendor == "amd" and data["coreMhz"] is not None:
                data["coreMhz"] /= 1e6
            if vendor == "amd":
                for key, clock in (("coreMhz", "sclk"), ("memoryMhz", "mclk")):
                    if data[key] is None:
                        active = re.search(r"^\s*\d+:\s*(\d+(?:\.\d+)?)\s*Mhz\s*\*",
                                           read(device / ("pp_dpm_" + clock)), re.I | re.M)
                        data[key] = number(active[1]) if active else None
    return data


def network_interface():
    links = SYS / "class/net"
    for family in ("-4", "-6"):
        routes = json.loads(command("ip", "-j", family, "route", "show", "default") or "[]")
        for route in sorted(routes, key=lambda item: item.get("metric", 0)):
            if route.get("dev") and (links / route["dev"]).exists():
                return route["dev"]
    return next((p.name for p in sorted(links.iterdir())
                 if p.name != "lo" and read(p / "operstate") == "up"), "")


def netlink_attributes(data):
    attributes = {}
    while len(data) >= 4:
        length, kind = struct.unpack_from("=HH", data)
        if length < 4 or length > len(data):
            break
        attributes[kind & 0x3fff] = data[4:length]
        data = data[(length + 3) & ~3:]
    return attributes


def wifi_station(interface):
    """Read negotiated station rates via the Linux nl80211 ABI, as iw link does."""
    def request(sock, family, operation, kind, value, dump=False):
        length = len(value) + 4
        attribute = struct.pack("=HH", length, kind) + value + bytes(-length % 4)
        payload = struct.pack("=BBH", operation, 1, 0) + attribute
        flags = 0x301 if dump else 1  # NLM_F_REQUEST and optionally NLM_F_DUMP
        sock.send(struct.pack("=IHHII", 16 + len(payload), family, flags, 1, 0) + payload)
        response = sock.recv(32768)
        if len(response) < 20:
            return {}
        size, kind = struct.unpack_from("=IH", response)
        return netlink_attributes(response[20:size]) if kind == family else {}

    try:
        with socket.socket(socket.AF_NETLINK, socket.SOCK_RAW, 16) as sock:  # NETLINK_GENERIC
            sock.settimeout(0.2)
            sock.bind((0, 0))
            # CTRL_CMD_GETFAMILY, CTRL_ATTR_FAMILY_NAME, CTRL_ATTR_FAMILY_ID.
            family = request(sock, 16, 3, 2, b"nl80211\0").get(1)
            if not family:
                return {}, ""
            index = struct.pack("=I", socket.if_nametoindex(interface))
            # NL80211_CMD_GET_STATION, NL80211_ATTR_IFINDEX, NL80211_ATTR_STA_INFO.
            station = request(sock, int.from_bytes(family, sys.byteorder), 17, 3, index, dump=True)
    except OSError:
        return {}, ""

    info = netlink_attributes(station.get(21, b""))
    rates = {}
    generations = []
    for kind, label in ((14, "Receive"), (8, "Send")):  # STA_INFO RX/TX_BITRATE
        rate = netlink_attributes(info.get(kind, b""))
        value = rate.get(5) or rate.get(1)  # RATE_INFO BITRATE32/BITRATE, in 100 kbit/s.
        if value:
            rates[label] = int.from_bytes(value, sys.byteorder) / 10
        for code, generation in ((19, 7), (13, 6), (6, 5), (2, 4)):
            if code in rate:
                generations.append(generation)
                break
    standards = {7: "7 (802.11be)", 6: "6 (802.11ax)", 5: "5 (802.11ac)", 4: "4 (802.11n)"}
    standard = "Wi-Fi " + standards[max(generations)] if generations else "Wi-Fi"
    return rates, standard


def wifi_properties(interface, nm_path):
    rates, standard = wifi_station(interface)
    speed = " · ".join(f"{label} {rate:g} Mb/s" for label, rate in rates.items())
    if not speed and nm_path.startswith("/org/freedesktop/NetworkManager/Devices/"):
        reply = command("busctl", "get-property", "org.freedesktop.NetworkManager", nm_path,
                        "org.freedesktop.NetworkManager.Device.Wireless", "Bitrate")
        bitrate = number(reply.removeprefix("u "))
        if bitrate:
            speed = f"{bitrate / 1000:g} Mb/s"
    aps = command("nmcli", "-t", "--escape", "no", "-f", "ACTIVE,FREQ,RATE,SSID", "device",
                  "wifi", "list", "--rescan", "no", "ifname", interface)
    active = next((line.split(":", 3) for line in aps.splitlines() if line.startswith("yes:")), [])
    frequency = 0
    ssid = None
    if len(active) == 4:
        frequency = number(active[1]) or 0
        ssid = active[3]
        maximum = number(active[2])
        if not speed and maximum:
            speed = f"{maximum:g} Mb/s (AP max)"
    band = ("60 GHz" if frequency >= 56000 else "6 GHz" if frequency >= 5925
            else "5 GHz" if frequency >= 4900 else "2.4 GHz" if frequency else "")
    return {"name": ssid, "link": " · ".join(filter(None, [standard or "Wi-Fi", band])), "speed": speed}


def network_properties(interface):
    if not interface:
        return {}
    net = SYS / "class/net" / interface
    device = net / "device"
    manufacturer = (VENDORS.get(read(device / "vendor"))
                    or command("nmcli", "--escape", "no", "-g", "GENERAL.VENDOR",
                               "device", "show", interface))
    settings = command("nmcli", "--escape", "no", "-g", "GENERAL.DBUS-PATH,GENERAL.CONNECTION",
                       "device", "show", interface)
    nm_path, _, profile = settings.partition("\n")
    data = {"manufacturer": manufacturer, "driver": (device / "driver").resolve().name
            if (device / "driver").is_symlink() else None, "address": read(net / "address")}
    if (net / "wireless").exists() or (net / "phy80211").exists():
        data.update(wifi_properties(interface, nm_path))
    else:
        speed = number(read(net / "speed"))
        data.update(link="Ethernet" if (device / "driver").exists() else None,
                    speed=f"{speed:g} Mb/s" if speed and speed > 0 else None)
    data["name"] = data.get("name") or (profile if profile != "--" else None)
    return data


def backing_disks(nodes):
    for node in nodes:
        if node.get("type") == "disk":
            yield node
        yield from backing_disks(node.get("children", []))


def storage_properties():
    mounts = json_command("findmnt", "-J", "-o", "SOURCE,FSTYPE,OPTIONS", "--target", "/")
    mount = next(iter(mounts.get("filesystems", [])), {})
    source = mount.get("source", "").split("[", 1)[0]
    root = {"filesystem": mount.get("fstype"), "volume": source}
    if mount:
        root["writable"] = "rw" in mount.get("options", "").split(",")
    if source.startswith("/dev/"):
        info = json_command("lsblk", "-bJs", "-o", "NAME,TYPE,SIZE,TRAN,MODEL,RO,RM", source)
        drives = {d["name"]: d for d in backing_disks(info.get("blockdevices", []))}
        if drives:
            root["device"] = ", ".join(drives)
            root["writable"] = root["writable"] and all(not d["ro"] for d in drives.values())
        if len(drives) == 1:
            drive = next(iter(drives.values()))
            transport = drive.get("tran")
            device = SYS / "class/block" / drive["name"] / "device"
            link = pcie_link(device) or pcie_link(device / "device")
            root.update(model=drive.get("model"), type={"nvme": "NVMe Drive", "sata": "SATA Drive",
                        "usb": "USB Drive", "mmc": "MMC Drive"}.get(transport, "Drive"),
                        capacity=drive["size"], removable=drive["rm"], link=link)
    return root


def swap_backing():
    types = set()
    for line in read(Path("/proc/swaps")).splitlines()[1:]:
        source, kind, *_ = line.rsplit(None, 4)
        if re.fullmatch(r"/dev/zram[0-9]+", source):
            types.add("zram")
        else:
            types.add({"file": "Swap file", "partition": "Block device"}.get(kind, kind))
    return " · ".join(sorted(types))


def slow_sample(page, pci, path):
    stat = os.statvfs("/")
    data = {"uptime": number(read(Path("/proc/uptime"))),
            "total": stat.f_blocks * stat.f_frsize,
            "used": (stat.f_blocks - stat.f_bfree) * stat.f_frsize,
            "available": stat.f_bavail * stat.f_frsize,
            "netInterface": network_interface()}
    if page == "swap":
        data["swapBacking"] = swap_backing()
    elif page == "disk":
        data["disk"] = storage_properties()
    elif page == "net":
        data["net"] = network_properties(data["netInterface"])
    elif page == "gpu" and path:
        device = Path(path)
        fields = pci_name(device)
        data["gpu"] = {"manufacturer": VENDORS.get(read(device / "vendor")) or fields.get("Vendor"),
                       "name": fields.get("Device"), "pci": pci,
                       "driver": (device / "driver").resolve().name
                       if (device / "driver").is_symlink() else None}
    return data


if __name__ == "__main__":
    mode, *args = sys.argv[1:]
    if mode == "detect":
        result = detect()
    elif mode == "gpu":
        result = gpu_sample(*args[:4], details=args[4] == "gpu")
    else:
        result = slow_sample(*args)
    print(json.dumps(result))
