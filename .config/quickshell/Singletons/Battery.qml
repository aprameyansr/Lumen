pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

/**
 * Live charge and notifications use UPower's display device. Hardware
 * properties come from the physical battery's Linux power-supply entry.
 */
Singleton {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property var physicalDevice: UPower.devices.values.find(device =>
        device.ready && device.isPresent && device.isLaptopBattery)
    readonly property string nativeName: physicalDevice?.nativePath.split("/").pop() ?? ""

    readonly property bool present: dev !== null && dev.ready && dev.isLaptopBattery && dev.isPresent
    readonly property real frac: dev ? Math.max(0, Math.min(1, dev.percentage)) : 0
    readonly property int pct: Math.round(frac * 100)
    readonly property int state: dev ? dev.state : UPowerDeviceState.Unknown

    readonly property bool charging: state === UPowerDeviceState.Charging
    readonly property bool full: state === UPowerDeviceState.FullyCharged
    readonly property bool discharging: state === UPowerDeviceState.Discharging
    readonly property bool low: !charging && pct <= 15

    readonly property real rateW: !dev ? 0 : (discharging ? -dev.changeRate : (charging ? dev.changeRate : 0))
    readonly property real capacityWh: dev ? dev.energyCapacity : 0

    property var hardware: ({})
    readonly property string deviceName: hardware.NAME || nativeName
    readonly property string modelName: hardware.MODEL_NAME || physicalDevice?.model || ""
    readonly property string manufacturer: hardware.MANUFACTURER || ""
    readonly property string technology: ({
        "li-ion": "Lithium Ion",
        "li-poly": "Lithium Polymer",
        "lifepo4": "Lithium Iron Phosphate",
        "nimh": "Nickel Metal Hydride",
        "nicd": "Nickel Cadmium",
        "lead acid": "Lead Acid"
    })[(hardware.TECHNOLOGY || "").toLowerCase()] ?? (hardware.TECHNOLOGY || "")
    readonly property string chargeCycles: /^\d+$/.test(hardware.CYCLE_COUNT ?? "") ? hardware.CYCLE_COUNT : ""
    readonly property string designCapacity: {
        const energy = Number(hardware.ENERGY_FULL_DESIGN);
        const charge = Number(hardware.CHARGE_FULL_DESIGN);
        const voltage = Number(hardware.VOLTAGE_MIN_DESIGN);
        if (energy > 0)
            return (energy / 1e6).toFixed(1) + " Wh";
        if (charge > 0 && voltage > 0)
            return (charge * voltage / 1e12).toFixed(1) + " Wh";
        return charge > 0 ? (charge / 1e3).toFixed(0) + " mAh" : "";
    }
    readonly property string health: {
        const healthDevice = physicalDevice ?? dev;
        if (healthDevice?.healthSupported && (!nativeName || deviceName === nativeName))
            return Math.round(healthDevice.healthPercentage) + "%";

        const fullEnergy = Number(hardware.ENERGY_FULL);
        const designEnergy = Number(hardware.ENERGY_FULL_DESIGN);
        if (fullEnergy > 0 && designEnergy > 0)
            return Math.round(100 * fullEnergy / designEnergy) + "%";

        const fullCharge = Number(hardware.CHARGE_FULL);
        const designCharge = Number(hardware.CHARGE_FULL_DESIGN);
        return fullCharge > 0 && designCharge > 0 ? Math.round(100 * fullCharge / designCharge) + "%" : "";
    }

    function refreshHardware() {
        hardwareProbe.running = true;
    }

    Process {
        id: hardwareProbe

        command: ["sh", "-c", `
            read_battery() {
                [ -r "$1/uevent" ] || return 1
                [ "$(cat "$1/type" 2>/dev/null)" = Battery ] || return 1
                [ "$(cat "$1/present" 2>/dev/null)" != 0 ] || return 1
                [ "$(cat "$1/scope" 2>/dev/null)" != Device ] || return 1
                cat "$1/uevent"
            }
            if [ -n "$1" ] && read_battery "/sys/class/power_supply/$1"; then
                exit
            fi
            for supply in /sys/class/power_supply/*; do
                read_battery "$supply" && exit
            done
        `, "battery-properties", root.nativeName]

        stdout: StdioCollector {
            onStreamFinished: {
                const values = Object.create(null);
                const prefix = "POWER_SUPPLY_";
                for (const line of text.split("\n")) {
                    const separator = line.indexOf("=");
                    if (separator > prefix.length && line.startsWith(prefix))
                        values[line.slice(prefix.length, separator)] = line.slice(separator + 1).trim();
                }
                root.hardware = values;
            }
        }
    }

    readonly property bool hasTime: !dev ? false : (charging ? dev.timeToFull > 0 : (discharging ? dev.timeToEmpty > 0 : false))
    readonly property string timeStr: !dev ? "" : (charging ? fmt(dev.timeToFull) : (discharging ? fmt(dev.timeToEmpty) : ""))

    readonly property string stateLabel: charging ? "Charging" : (full ? "On AC · Full" : (discharging ? "Discharging" : "On AC"))

    property bool lowNotified: false
    property bool criticalNotified: false

    function notifyBattery(title, body, urgency, icon) {
        Quickshell.execDetached(["notify-send", "-a", "Lumen", "-u", urgency, "-i", icon, title, body]);
    }

    function checkBatteryNotifications() {
        if (!present)
            return;

        // Never notify while charging or on AC.
        // Reset the flags so a future discharge can trigger notifications again.
        if (!discharging) {
            lowNotified = false;
            criticalNotified = false;
            return;
        }

        // Critical battery: 5% or below.
        if (pct <= 5 && !criticalNotified) {
            criticalNotified = true;
            notifyBattery("Battery critical", "Battery is critically low at " + pct + "%.", "critical", "/usr/share/icons/Adwaita/symbolic/legacy/battery-empty-symbolic.svg");
            return;
        }

        // Low battery: 15% or below.
        if (pct <= 15 && !lowNotified) {
            lowNotified = true;
            notifyBattery("Battery low", "Battery is at " + pct + "%.", "normal", "/usr/share/icons/Adwaita/symbolic/status/battery-level-10-symbolic.svg");
        }
    }

    onPctChanged: checkBatteryNotifications()
    onDischargingChanged: checkBatteryNotifications()

    function fmt(sec) {
        var s = Math.max(0, Math.round(sec));
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);
        if (h > 0)
            return h + "h " + m + "m";
        return m + "m";
    }
}
