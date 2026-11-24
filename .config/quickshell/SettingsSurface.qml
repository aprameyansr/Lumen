pragma ComponentBehavior: Bound

import QtQuick

// Shared settings row navigation and focus indicator.
PillSurface {
    id: root

    mTop: 15
    mLeft: 19
    mRight: 19
    mBottom: 14

    signal requestSurface(string name)

    property Item focusRowItem: null
    property int kbIndex: -1
    property var rows: []

    function reportRowHover(item, hovered) {
        if (hovered) {
            focusRowItem = item;
            kbIndex = rowIndexOf(item);
        }
    }
    onActiveChanged: if (!active) {
        focusRowItem = null;
        kbIndex = -1;
    }

    function rowIndexOf(item) {
        return rows.findIndex(row => row.item === item);
    }

    /** Step a seg row's value by `dir`, wrapping at both ends like a mouse click. */
    function segCycle(r, dir) {
        const n = r.vals.length;
        if (n === 0)
            return;
        const i = r.vals.indexOf(r.get());
        r.set(r.vals[(((i < 0 ? 0 : i) + dir) % n + n) % n]);
    }

    function kbMove(dir) {
        if (!rows.length)
            return;
        kbIndex = Math.max(0, Math.min(rows.length - 1, (kbIndex < 0 ? 0 : kbIndex + dir)));
        focusRowItem = rows[kbIndex].item;
    }

    function kbAdjust(dir) {
        if (!rows.length)
            return;
        if (kbIndex < 0) {
            kbIndex = 0;
            focusRowItem = rows[0].item;
        }
        const r = rows[kbIndex];
        if (!r)
            return;
        if (r.kind === "seg")
            segCycle(r, dir);
        else if (r.kind === "toggle")
            r.set(dir > 0);
        else if (r.kind === "scrub")
            r.bump(dir);
    }

    function kbActivate() {
        const row = rows[kbIndex];
        if (row?.kind === "scrub") {
            row.run?.();
            return;
        }
        activateControl(row);
    }

    function activateControl(row) {
        if (!row)
            return;
        switch (row.kind) {
        case "toggle":
            row.set(!row.get());
            break;
        case "nav":
            root.requestSurface(row.surface);
            break;
        case "seg":
            segCycle(row, 1);
            break;
        case "action":
            row.run();
            break;
        }
    }

    function activateRow(item) {
        const index = rowIndexOf(item);
        if (index < 0)
            return;
        kbIndex = index;
        focusRowItem = item;
        activateControl(rows[index]);
    }

    readonly property bool rowFocused: focusRowItem !== null && active

    readonly property point rowPoint: {
        void root.width;
        void root.height;
        void root.focusRowItem;
        if (!focusRowItem)
            return Qt.point(4 * root.s, root.height / 2);
        return focusRowItem.mapToItem(root, 4 * root.s, focusRowItem.height / 2);
    }

    ameForm: rowFocused ? "rowseam" : "off"
    amePoint: rowPoint
}
