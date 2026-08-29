pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.UPower

/**
 * Laptop-battery state for the pill, sourced from UPower's display device and
 * gated so a desktop without a battery reports `present` false (the hover
 * cluster and 蓄 surface stay hidden). Exposes percentage, charge state, a
 * signed draw/charge wattage, capacity and optional health, plus a formatted
 * time-to-empty/full string. `low` flags a discharging battery at or below 15%.
 */
Singleton {
    id: root

    readonly property var dev: UPower.displayDevice

    readonly property bool present: dev !== null && dev.ready && dev.isLaptopBattery && dev.isPresent
    readonly property real frac: dev ? Math.max(0, Math.min(1, dev.percentage)) : 0
    readonly property int pct: Math.round(frac * 100)
    readonly property int state: dev ? dev.state : UPowerDeviceState.Unknown

    readonly property bool charging: state === UPowerDeviceState.Charging
    readonly property bool full: state === UPowerDeviceState.FullyCharged || pct >= 100
    readonly property bool discharging: state === UPowerDeviceState.Discharging
    readonly property bool low: !charging && pct <= 15

    readonly property real rateW: !dev ? 0
        : (discharging ? -dev.changeRate : (charging ? dev.changeRate : 0))
    readonly property real capacityWh: dev ? dev.energyCapacity : 0

    readonly property bool healthSupported: dev ? dev.healthSupported : false
    readonly property int health: dev ? Math.round(dev.healthPercentage) : 0

    readonly property bool hasTime: !dev ? false
        : (charging ? dev.timeToFull > 0 : (discharging ? dev.timeToEmpty > 0 : false))
    readonly property string timeStr: !dev ? ""
        : (charging ? fmt(dev.timeToFull) : (discharging ? fmt(dev.timeToEmpty) : ""))

    readonly property string stateLabel: charging ? "Charging"
        : (full ? "On AC · Full"
        : (discharging ? "Discharging" : "On AC"))

    property bool lowNotified: false
    property bool criticalNotified: false

    function notifyBattery(title, body, urgency, icon) {
        Quickshell.execDetached([
            "notify-send",
            "-a", "Ricelin",
            "-u", urgency,
            "-i", icon,
            title,
            body
        ]);
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
            notifyBattery(
                "Battery critical",
                "Battery is critically low at " + pct + "%.",
                "critical",
                "/usr/share/icons/breeze/status/32/battery-empty.svg"
            );
            return;
        }

        // Low battery: 15% or below.
        if (pct <= 15 && !lowNotified) {
            lowNotified = true;
            notifyBattery(
                "Battery low",
                "Battery is at " + pct + "%.",
                "normal",
                "/usr/share/icons/breeze/status/32/battery-low.svg"
            );
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