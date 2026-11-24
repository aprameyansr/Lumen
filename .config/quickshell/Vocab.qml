pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import "Singletons"

/**
 * 語 VOCABULARY sub-surface (Settings > Input > Dictation): names and terms the
 * speech model gets wrong, with the ways it mishears each one (its "forms").
 * Dictation swaps a form, or a close sound-alike, for the real spelling before
 * typing.
 *
 * Four views share the surface:
 *  - list: every word with a count of its forms. Enter or a click opens it,
 *    Delete or ✕ drops the word, the dashed bar adds one, Import / Export below.
 *  - word: one word's forms, each removable on its own (Delete or ✕). A form made
 *    only of everyday English ("April", "I know") would rewrite normal speech,
 *    so it is flagged and skipped by dictation until you choose to use it
 *    (Enter or the chip toggles). Then Teach more and Remove word.
 *  - add: the exact spelling. A word that's already everyday English gets a note
 *    that the model should know it, and a second Enter adds it anyway; a word
 *    already in the list just opens.
 *  - teach: say the word `goal` times on the dictation key. Each take is
 *    transcribed raw (Dictate.teaching) and kept as a form; the last one saves
 *    and lands on the word view so the new forms and any flags are in sight.
 *    Enter saves early, Esc backs out without saving.
 *
 * The list lives in ~/.local/share/lumen-dictate/vocab.json. Every change is
 * written atomically and the dictation service is told to reload at once, so a
 * removed word or form stops applying on the very next take.
 *
 * Import and Export carry the list between machines as one JSON file. The page
 * steps aside for the system file picker (the pill sits on the overlay layer
 * and holds the keyboard, so a dialog would open beneath it), a notification
 * reports the result, and the page comes back. Import merges: new words are
 * added, words already here gain any new forms, nothing is lost.
 */
SettingsSurface {
    id: root

    implicitHeight: content.implicitHeight

    readonly property string vocabPath: Dictate.svcDir + "/vocab.json"
    readonly property int goal: 3

    /** [{ word, heard: [forms], pinned: [common forms used anyway] }] */
    property var words: []
    /** "list" | "word" | "add" | "teach" */
    property string view: "list"
    /** Word open in the word view (or being taught). */
    property string current: ""
    property var teachHeard: []
    property int teachTakes: 0
    property string addText: ""
    property bool addWarn: false
    property string lastHeard: ""

    /** Search over the list: live, fuzzy, matched against words and their forms. */
    property string query: ""

    readonly property bool typing: root.active && (root.view === "add" || searchField.activeFocus)

    /**
     * Fuzzy score of `q` in `s`: every query letter must appear in order. Runs of
     * consecutive letters, a match at the start and at word starts score higher,
     * so "nik" ranks Nikolai above a word that merely contains n, i and k.
     * -1 when it doesn't match.
     */
    function fuzzy(q, s) {
        q = q.toLowerCase();
        s = s.toLowerCase();
        let score = 0, run = 0, si = 0;
        for (let qi = 0; qi < q.length; qi++) {
            const c = q[qi];
            if (c === " ")
                continue;
            const at = s.indexOf(c, si);
            if (at < 0)
                return -1;
            run = at === si ? run + 1 : 1;
            score += 1 + run * 2 + (at === 0 ? 6 : 0) + (at > 0 && /[\s\-]/.test(s[at - 1]) ? 3 : 0) - Math.min(3, at - si) * 0.5;
            si = at + 1;
        }
        return score;
    }

    /** What the list shows: everything A to Z, or the best fuzzy matches first. */
    readonly property var shown: {
        const byName = (a, b) => a.word.localeCompare(b.word, undefined, {
                sensitivity: "base"
            });
        const q = root.query.trim();
        if (q.length === 0)
            return root.words.slice().sort(byName);
        const scored = [];
        for (const w of root.words) {
            let best = root.fuzzy(q, w.word);
            for (const h of w.heard)
                best = Math.max(best, root.fuzzy(q, h) - 2);
            if (best >= 0)
                scored.push({
                    w: w,
                    sc: best
                });
        }
        scored.sort((a, b) => b.sc - a.sc || byName(a.w, b.w));
        return scored.map(x => x.w);
    }

    /** A printable key on the list jumps into search with that letter. */
    function startSearch(ch) {
        if (root.view !== "list")
            return;
        searchField.forceActiveFocus();
        searchField.insert(searchField.cursorPosition, ch);
    }

    function endSearch(clear) {
        if (clear)
            searchField.text = "";
        searchField.focus = false;
    }

    /** Enter in search: the selected result, else the top one, else add what was typed. */
    function searchEnter() {
        if (root.kbIndex >= 0 && root.kbIndex < root.rows.length) {
            root.kbActivate();
            return;
        }
        if (root.shown.length > 0) {
            root.openWord(root.shown[0].word);
            return;
        }
        const q = root.query.trim();
        if (q.length > 0) {
            root.openAdd();
            root.addText = q;
        }
    }
    readonly property var currentEntry: {
        const i = root.indexOfWord(root.current);
        return i >= 0 ? root.words[i] : null;
    }

    /** The row seam follows keyboard rows; the add and teach views have none. */
    onViewChanged: {
        root.focusRowItem = null;
        root.kbIndex = -1;
        /**
         * The hidden add field would otherwise keep its claim on focus, so the
         * next time the page opens Esc lands in it instead of closing the page.
         */
        if (root.view !== "add")
            addField.focus = false;
        searchField.focus = false;
    }
    ameForm: (root.view === "list" || root.view === "word") && rowFocused ? "rowseam" : "off"

    /** The seam rides the focused row through list scrolling too. */
    amePoint: {
        void root.width;
        void root.height;
        void wordFlick.contentY;
        const it = root.focusRowItem;
        return it ? it.mapToItem(root, 4 * root.s, it.height / 2) : Qt.point(4 * root.s, root.height / 2);
    }

    /** Keep a keyboard-focused word row inside the scrolled list. */
    onFocusRowItemChanged: {
        const it = root.focusRowItem;
        if (!it || it.parent !== wordCol || !wordFlick.interactive)
            return;
        const pad = 6 * root.s;
        if (it.y - pad < wordFlick.contentY)
            wordFlick.contentY = Math.max(0, it.y - pad);
        else if (it.y + it.height + 14 * root.s + pad > wordFlick.contentY + wordFlick.height)
            wordFlick.contentY = Math.min(wordFlick.contentHeight - wordFlick.height, it.y + it.height + 14 * root.s + pad - wordFlick.height);
    }

    // ── everyday English ──

    property var common: ({})
    readonly property var contractions: ["i'm", "i've", "i'll", "i'd", "don't", "can't", "won't", "it's", "isn't", "didn't", "doesn't", "wasn't", "aren't", "weren't", "couldn't", "wouldn't", "shouldn't", "haven't", "hasn't", "hadn't", "you're", "you'll", "you've", "you'd", "we're", "we'll", "we've", "they're", "they'll", "they've", "that's", "there's", "what's", "let's", "he's", "she's", "who's", "here's"]

    FileView {
        path: Dictate.svcDir + "/common-words.txt"
        printErrors: false
        onLoaded: {
            const set = {};
            for (const w of text().split("\n"))
                if (w.trim().length)
                    set[w.trim().toLowerCase()] = true;
            for (const c of root.contractions)
                set[c] = true;
            root.common = set;
        }
    }

    function norm(s) {
        return s.toLowerCase().replace(/-/g, " ").replace(/[^\w' ]+/g, " ").replace(/\s+/g, " ").trim();
    }

    /** Every word of the phrase is among the ~10k most common English words. */
    function isCommon(phrase) {
        const ws = root.norm(phrase).split(" ").filter(w => w.length);
        return ws.length > 0 && ws.every(w => root.common[w] === true || root.common[w.replace(/'/g, "")] === true);
    }

    function isPinned(entry, form) {
        const k = root.norm(form);
        return (entry.pinned || []).some(p => root.norm(p) === k);
    }

    function skipped(entry, form) {
        return root.isCommon(form) && !root.isPinned(entry, form);
    }

    function skippedCount(entry) {
        return entry.heard.filter(h => root.skipped(entry, h)).length;
    }

    // ── navigation ──

    /** Pill.qml asks before stepping the surface back. */
    function back() {
        if (root.view === "list")
            return false;
        if (root.view === "teach" && root.currentEntry) {
            root.openWord(root.current);
            return true;
        }
        root.toList();
        return true;
    }

    function resetTeach() {
        root.teachHeard = [];
        root.teachTakes = 0;
        root.lastHeard = "";
        doneTimer.stop();
    }

    function toList() {
        root.resetTeach();
        root.view = "list";
        root.current = "";
        root.addText = "";
        root.addWarn = false;
    }

    function openWord(word) {
        root.resetTeach();
        root.current = word;
        root.view = "word";
    }

    function openAdd() {
        root.addText = "";
        root.addWarn = false;
        root.view = "add";
        Qt.callLater(addField.forceActiveFocus);
    }

    /** Enter in the add field. */
    function submitAdd() {
        const w = root.addText.trim();
        if (w.length === 0)
            return;
        const i = root.indexOfWord(w);
        if (i >= 0) {
            root.openWord(root.words[i].word);
            return;
        }
        if (root.isCommon(w) && !root.addWarn) {
            root.addWarn = true;
            return;
        }
        root.startTeach(w);
    }

    function indexOfWord(w) {
        const k = w.trim().toLowerCase();
        for (let i = 0; i < root.words.length; i++)
            if (root.words[i].word.toLowerCase() === k)
                return i;
        return -1;
    }

    function startTeach(word) {
        const w = word.trim();
        if (w.length === 0)
            return;
        const i = root.indexOfWord(w);
        root.resetTeach();
        root.current = i >= 0 ? root.words[i].word : w;
        root.teachHeard = i >= 0 ? root.words[i].heard.slice() : [];
        root.view = "teach";
    }

    function addHeard(text) {
        const t = text.replace(/[.,!?;:]+$/, "").trim();
        if (t.length === 0)
            return;
        root.lastHeard = t;
        const k = t.toLowerCase();
        if (k !== root.current.toLowerCase() && !root.teachHeard.some(h => h.toLowerCase() === k))
            root.teachHeard = root.teachHeard.concat([t]);
        root.teachTakes += 1;
        if (root.teachTakes >= root.goal)
            doneTimer.restart();
    }

    function saveTeach() {
        if (root.view !== "teach")
            return;
        doneTimer.stop();
        const next = root.words.slice();
        const i = root.indexOfWord(root.current);
        const entry = {
            word: root.current,
            heard: root.teachHeard,
            pinned: i >= 0 ? (next[i].pinned || []) : []
        };
        if (i >= 0)
            next[i] = entry;
        else
            next.push(entry);
        root.commit(next);
        root.openWord(root.current);
        /** A brand-new word lands with "Add another word" selected, so Enter goes straight on. */
        if (i < 0)
            Qt.callLater(root.focusAddAnother);
    }

    function focusAddAnother() {
        if (root.view !== "word")
            return;
        const idx = root.rowIndexOf(addAnotherRow);
        if (idx >= 0) {
            root.kbIndex = idx;
            root.focusRowItem = addAnotherRow;
        }
    }

    function removeAt(i) {
        if (i < 0 || i >= root.words.length)
            return;
        const next = root.words.slice();
        next.splice(i, 1);
        root.commit(next);
        root.kbIndex = Math.min(root.kbIndex, next.length);
        if (root.kbIndex >= 0 && root.kbIndex < root.rows.length)
            root.focusRowItem = root.rows[root.kbIndex].item;
    }

    function removeWord(word) {
        const i = root.indexOfWord(word);
        if (i < 0)
            return;
        const next = root.words.slice();
        next.splice(i, 1);
        root.commit(next);
        Qt.callLater(function () {
            root.kbIndex = Math.min(root.kbIndex, root.rows.length - 1);
            root.focusRowItem = root.kbIndex >= 0 ? root.rows[root.kbIndex].item : null;
        });
    }

    function removeCurrent() {
        const i = root.indexOfWord(root.current);
        if (i >= 0)
            root.removeAt(i);
        root.toList();
    }

    function removeForm(form) {
        const i = root.indexOfWord(root.current);
        if (i < 0)
            return;
        const e = root.words[i];
        const k = root.norm(form);
        const next = root.words.slice();
        next[i] = {
            word: e.word,
            heard: e.heard.filter(h => root.norm(h) !== k),
            pinned: (e.pinned || []).filter(p => root.norm(p) !== k)
        };
        root.commit(next);
    }

    function togglePin(form) {
        const i = root.indexOfWord(root.current);
        if (i < 0 || !root.isCommon(form))
            return;
        const e = root.words[i];
        const k = root.norm(form);
        const pinned = (e.pinned || []).filter(p => root.norm(p) !== k);
        if (!root.isPinned(e, form))
            pinned.push(form);
        const next = root.words.slice();
        next[i] = {
            word: e.word,
            heard: e.heard.slice(),
            pinned: pinned
        };
        root.commit(next);
    }

    /** Delete key: a word on the list, a form on the word view. */
    function deleteFocused() {
        if (root.view === "list") {
            if (root.kbIndex >= 0 && root.kbIndex < root.shown.length)
                root.removeWord(root.shown[root.kbIndex].word);
        } else if (root.view === "word" && root.currentEntry) {
            const f = root.currentEntry.heard;
            if (root.kbIndex >= 0 && root.kbIndex < f.length) {
                const keep = root.kbIndex;
                root.removeForm(f[root.kbIndex]);
                Qt.callLater(function () {
                    root.kbIndex = Math.min(keep, root.rows.length - 1);
                    root.focusRowItem = root.kbIndex >= 0 ? root.rows[root.kbIndex].item : null;
                });
            }
        }
    }

    /** Clear the whole vocabulary (the list's hold-to-wipe); focus falls back off the list. */
    function wipeAll() {
        root.kbIndex = -1;
        root.focusRowItem = null;
        root.commit([]);
    }

    /** Held Shift+Delete on the list: drive the wipe heat like a pointer hold. */
    function wipePress() {
        if (root.view === "list" && vocabWipe.visible)
            vocabWipe.keyPress();
    }
    function wipeRelease() {
        vocabWipe.keyRelease();
    }

    function commit(arr) {
        root.words = arr;
        writer.setText(JSON.stringify({
            words: arr
        }, null, 2) + "\n");
    }

    // ── import / export ──

    function notify(body) {
        notifyProc.command = ["notify-send", "-a", "Dictation", "-i", "accessories-dictionary", "Vocabulary", body];
        notifyProc.running = true;
    }

    function exportList() {
        if (root.words.length === 0)
            return;
        root.requestClose();
        exportPick.running = true;
    }

    function importList() {
        root.requestClose();
        importPick.running = true;
    }

    function merge(incoming) {
        const next = root.words.map(w => ({
                    word: w.word,
                    heard: w.heard.slice(),
                    pinned: (w.pinned || []).slice()
                }));
        let added = 0, grew = 0;
        for (const w of incoming) {
            const k = w.word.toLowerCase();
            const cur = next.find(x => x.word.toLowerCase() === k);
            if (!cur) {
                next.push({
                    word: w.word,
                    heard: w.heard.slice(),
                    pinned: w.pinned.slice()
                });
                added++;
                continue;
            }
            let more = false;
            for (const h of w.heard)
                if (!cur.heard.some(x => x.toLowerCase() === h.toLowerCase())) {
                    cur.heard.push(h);
                    more = true;
                }
            for (const p of w.pinned)
                if (!cur.pinned.some(x => x.toLowerCase() === p.toLowerCase()))
                    cur.pinned.push(p);
            if (more)
                grew++;
        }
        root.commit(next);
        return {
            added: added,
            grew: grew
        };
    }

    function plural(n, one) {
        return n + " " + one + (n === 1 ? "" : "s");
    }

    Process {
        id: notifyProc
    }

    Process {
        id: exportPick
        command: ["zenity", "--file-selection", "--save", "--title=Export vocabulary", "--filename=" + Dictate.home + "/lumen-vocabulary.json", "--file-filter=Vocabulary (*.json) | *.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let path = this.text.trim();
                if (path.length === 0) {
                    root.requestSurface("vocab");
                    return;
                }
                if (!/\.json$/i.test(path))
                    path += ".json";
                exportWrite.target = path;
                exportWrite.command = ["sh", "-c", "printf '%s\n' \"$2\" > \"$1\"", "_", path, JSON.stringify({
                        format: "lumen-vocabulary",
                        version: 1,
                        words: root.words
                    }, null, 2)];
                exportWrite.running = true;
            }
        }
    }

    Process {
        id: exportWrite
        property string target: ""
        onExited: code => {
            root.notify(code === 0 ? "Exported " + root.plural(root.words.length, "word") + " to " + exportWrite.target.replace(Dictate.home, "~") : "Couldn't write " + exportWrite.target.replace(Dictate.home, "~"));
            root.requestSurface("vocab");
        }
    }

    Process {
        id: importPick
        command: ["zenity", "--file-selection", "--title=Import vocabulary", "--filename=" + Dictate.home + "/", "--file-filter=Vocabulary (*.json) | *.json", "--file-filter=All files | *"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = this.text.trim();
                if (path.length === 0) {
                    root.requestSurface("vocab");
                    return;
                }
                importRead.command = ["cat", "--", path];
                importRead.running = true;
            }
        }
    }

    Process {
        id: importRead
        stdout: StdioCollector {
            onStreamFinished: {
                const incoming = root.parse(this.text);
                if (incoming.length === 0) {
                    root.notify("That file has no vocabulary in it");
                } else {
                    const r = root.merge(incoming);
                    root.notify(r.added === 0 && r.grew === 0 ? "Everything in that file was already here" : "Added " + root.plural(r.added, "word") + (r.grew > 0 ? ", sharpened " + r.grew : ""));
                }
                root.requestSurface("vocab");
            }
        }
    }

    function parse(text) {
        try {
            const d = JSON.parse(text);
            const arr = Array.isArray(d) ? d : (d.words || []);
            return arr.map(w => typeof w === "string" ? {
                    word: w,
                    heard: []
                } : w).filter(w => w && w.word && String(w.word).trim().length > 0).map(w => ({
                        word: String(w.word).trim(),
                        heard: (w.heard || []).map(String),
                        pinned: (w.pinned || []).map(String)
                    }));
        } catch (e) {
            return [];
        }
    }

    Timer {
        id: doneTimer
        interval: 700
        onTriggered: root.saveTeach()
    }

    Connections {
        target: Dictate
        function onHeard(text) {
            if (root.view === "teach")
                root.addHeard(text);
        }
    }

    Binding {
        target: Dictate
        property: "teaching"
        value: root.view === "teach" && root.active
        restoreMode: Binding.RestoreValue
    }

    onActiveChanged: {
        if (active)
            vocabFile.reload();
        else {
            root.toList();
            vocabWipe.cancel();
        }
        addField.focus = false;
        searchField.focus = false;
        searchField.text = "";
    }

    FileView {
        id: vocabFile
        path: root.vocabPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: root.words = root.parse(text())
        onFileChanged: reload()
    }

    FileView {
        id: writer
        path: root.vocabPath
        atomicWrites: true
        printErrors: false
        onSaved: Dictate.send({
            cmd: "reload"
        })
        onSaveFailed: err => console.log("vocab: write failed: " + err)
    }

    // ── row registry ──

    property int rowsRev: 0
    rows: {
        void root.rowsRev;
        void root.view;
        void root.words;
        const r = [];
        if (root.view === "list") {
            void root.shown;
            for (let i = 0; i < wordRep.count; i++) {
                const it = wordRep.itemAt(i);
                if (it && root.shown[i])
                    r.push({
                        item: it,
                        kind: "action",
                        run: (function (w) {
                                return function () {
                                    root.openWord(w);
                                };
                            })(root.shown[i].word)
                    });
            }
            r.push({
                item: addRow,
                kind: "action",
                run: root.openAdd
            });
            r.push({
                item: importRow,
                kind: "action",
                run: root.importList
            });
            r.push({
                item: exportRow,
                kind: "action",
                run: root.exportList
            });
        } else if (root.view === "word") {
            for (let i = 0; i < formRep.count; i++) {
                const it = formRep.itemAt(i);
                if (it && it.form !== undefined)
                    r.push({
                        item: it,
                        kind: "action",
                        run: (function (f) {
                                return function () {
                                    root.togglePin(f);
                                };
                            })(it.form)
                    });
            }
            r.push({
                item: teachMoreRow,
                kind: "action",
                run: function () {
                    root.startTeach(root.current);
                }
            });
            r.push({
                item: addAnotherRow,
                kind: "action",
                run: root.openAdd
            });
            r.push({
                item: removeWordRow,
                kind: "action",
                run: root.removeCurrent
            });
        }
        return r;
    }

    component Hint: Text {
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 9.5 * root.s
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1 * root.s
    }

    Column {
        id: content
        z: 100
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        SettingsHeader {
            s: root.s
            glyph: "語"
            title: "VOCABULARY"
            showBack: true
        }

        Item {
            width: 1
            height: 8 * root.s
        }

        // ── list ──

        Column {
            width: parent.width
            visible: root.view === "list"
            spacing: 0

            Item {
                width: parent.width
                height: visible ? 28 * root.s : 0
                visible: root.words.length > 0

                Text {
                    id: searchGlyph
                    anchors.left: parent.left
                    anchors.leftMargin: 4 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Flags.showGlyphs
                    width: Flags.showGlyphs ? implicitWidth : 0
                    text: "探"
                    color: Theme.dim
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 15 * root.s
                }

                TextField {
                    id: searchField
                    anchors.left: searchGlyph.right
                    anchors.leftMargin: Flags.showGlyphs ? 9 * root.s : 4 * root.s
                    anchors.right: vocabWipe.left
                    anchors.rightMargin: 8 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    background: null
                    padding: 0
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 13 * root.s
                    placeholderText: "type to search " + root.plural(root.words.length, "word")
                    placeholderTextColor: Theme.faint
                    selectByMouse: true
                    selectionColor: Theme.verm
                    onTextChanged: {
                        root.query = text;
                        root.kbIndex = -1;
                        root.focusRowItem = null;
                        wordFlick.contentY = 0;
                    }
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Down) {
                            root.kbMove(1);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Up) {
                            root.kbMove(-1);
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            root.searchEnter();
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Escape) {
                            root.endSearch(text.length > 0);
                            e.accepted = true;
                        }
                    }
                }

                Rectangle {
                    anchors.left: searchField.left
                    anchors.right: searchField.right
                    anchors.top: searchField.bottom
                    anchors.topMargin: 3 * root.s
                    height: 1
                    color: Theme.faint
                    opacity: searchField.activeFocus ? 0.7 : 0.18
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Motion.standard
                            easing.type: Motion.easeStandard
                        }
                    }
                }

                /** Wipe heat over the search underline, as on the clipboard. */
                Rectangle {
                    anchors.right: searchField.right
                    anchors.top: searchField.bottom
                    anchors.topMargin: 3 * root.s
                    height: 1
                    width: searchField.width * vocabWipe.hold
                    visible: vocabWipe.holding
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0.0
                            color: Qt.alpha(Theme.vermLit, 0.15)
                        }
                        GradientStop {
                            position: 1.0
                            color: Theme.vermLit
                        }
                    }
                }

                /** 掃 hold to wipe the whole vocabulary (or a held Shift+Delete). */
                Item {
                    id: vocabWipe
                    anchors.right: parent.right
                    anchors.rightMargin: 4 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16 * root.s
                    height: 16 * root.s

                    readonly property real hold: vocabWipeHeat.hold
                    readonly property bool holding: vocabWipeHeat.holding
                    readonly property color tone: holding ? Theme.vermLit : (vocabWipeArea.containsMouse ? Theme.cream : Theme.faint)

                    function keyPress() {
                        vocabWipeHeat.press();
                    }
                    function keyRelease() {
                        vocabWipeHeat.release();
                    }
                    function cancel() {
                        vocabWipeHeat.cancel();
                    }

                    Tooltip {
                        s: root.s
                        title: "hold to wipe"
                        show: vocabWipeArea.containsMouse || vocabWipe.holding
                    }

                    Text {
                        visible: Flags.showGlyphs
                        anchors.centerIn: parent
                        text: "掃"
                        color: vocabWipe.tone
                        font.family: Theme.fontJp
                        font.pixelSize: 12 * root.s
                        Behavior on color {
                            ColorAnimation {
                                duration: Motion.fast
                            }
                        }
                    }

                    GlyphIcon {
                        visible: !Flags.showGlyphs
                        anchors.centerIn: parent
                        width: 12 * root.s
                        height: 12 * root.s
                        name: "trash"
                        color: vocabWipe.tone
                        Behavior on color {
                            ColorAnimation {
                                duration: Motion.fast
                            }
                        }
                    }

                    HeatHold {
                        id: vocabWipeHeat
                        onConfirmed: root.wipeAll()
                    }

                    MouseArea {
                        id: vocabWipeArea
                        anchors.fill: parent
                        anchors.margins: -5 * root.s
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: vocabWipeHeat.press()
                        onReleased: vocabWipeHeat.release()
                        onExited: vocabWipeHeat.cancel()
                    }
                }
            }

            Item {
                width: 1
                height: visible ? 6 * root.s : 0
                visible: root.words.length > 0
            }

            Text {
                width: parent.width
                visible: root.words.length === 0 || (root.query.trim().length > 0 && root.shown.length === 0)
                leftPadding: 9 * root.s
                rightPadding: 9 * root.s
                bottomPadding: 6 * root.s
                text: root.words.length === 0 ? "Names and terms dictation gets wrong. Add one, say it a few times, and it's spelled right from then on." : "Nothing matches “" + root.query.trim() + "”. Press Enter to add it."
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
                lineHeight: 1.2
            }

            /**
             * The word list scrolls past `maxH` instead of growing the page off
             * screen; keyboard focus scrolls its row into view.
             */
            Flickable {
                id: wordFlick
                readonly property real maxH: 236 * root.s
                width: parent.width
                height: Math.min(wordCol.implicitHeight, maxH)
                contentHeight: wordCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                Behavior on contentY {
                    enabled: !wordFlick.moving
                    NumberAnimation {
                        duration: Motion.fast
                        easing.type: Easing.OutCubic
                    }
                }

                Column {
                    id: wordCol
                    width: parent.width

                    Repeater {
                        id: wordRep
                        model: root.shown
                        onItemAdded: root.rowsRev++
                        onItemRemoved: root.rowsRev++

                        delegate: Item {
                            id: wrow
                            required property int index
                            required property var modelData

                            readonly property bool focused: root.focusRowItem === wrow
                            readonly property bool expanded: whover.hovered || wrow.focused
                            readonly property int skips: {
                                void root.common;
                                return root.skippedCount(wrow.modelData);
                            }
                            readonly property string caption: wrow.modelData.heard.length === 0 ? "Not taught yet" : root.plural(wrow.modelData.heard.length, "form") + (wrow.skips > 0 ? " · " + wrow.skips + " skipped as everyday English" : "")

                            width: parent ? parent.width : 0
                            height: 30 * root.s + (wrow.expanded ? 14 * root.s : 0)
                            clip: true
                            Behavior on height {
                                NumberAnimation {
                                    duration: Motion.fast
                                    easing.type: Easing.OutCubic
                                }
                            }

                            HoverHandler {
                                id: whover
                                onHoveredChanged: root.reportRowHover(wrow, hovered)
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: 3 * root.s
                                anchors.bottomMargin: 3 * root.s
                                radius: 9 * root.s
                                color: wrow.expanded ? Theme.frameBg : "transparent"
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Motion.fast
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activateRow(wrow)
                            }

                            GlyphIcon {
                                id: wicon
                                anchors.left: parent.left
                                anchors.leftMargin: 9 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                width: 15 * root.s
                                height: 15 * root.s
                                name: "type"
                                color: wrow.focused ? Theme.cream : Theme.subtle
                                stroke: 1.8
                            }

                            Column {
                                anchors.left: wicon.right
                                anchors.leftMargin: 9 * root.s
                                anchors.right: wctl.left
                                anchors.rightMargin: 8 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2 * root.s

                                Text {
                                    width: parent.width
                                    text: wrow.modelData.word
                                    color: Theme.cream
                                    font.family: Theme.font
                                    font.pixelSize: 12.5 * root.s
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    visible: wrow.expanded
                                    text: wrow.caption
                                    color: Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: 9 * root.s
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                id: wctl
                                anchors.right: parent.right
                                anchors.rightMargin: 6 * root.s
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4 * root.s

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !wrow.expanded && wrow.skips > 0
                                    width: 5 * root.s
                                    height: 5 * root.s
                                    radius: width / 2
                                    color: Theme.flameGlow
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !wrow.expanded
                                    text: wrow.modelData.heard.length
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 11 * root.s
                                    font.weight: Font.DemiBold
                                    font.features: {
                                        "tnum": 1
                                    }
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: wrow.expanded
                                    width: 22 * root.s
                                    height: 22 * root.s
                                    radius: 6 * root.s
                                    color: rmArea.containsMouse ? Qt.alpha(Theme.verm, 0.16) : "transparent"
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Motion.fast
                                        }
                                    }

                                    GlyphIcon {
                                        anchors.centerIn: parent
                                        width: 11 * root.s
                                        height: 11 * root.s
                                        name: "close"
                                        color: rmArea.containsMouse ? Theme.vermLit : Theme.iconDim
                                        stroke: 2
                                    }

                                    MouseArea {
                                        id: rmArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.removeWord(wrow.modelData.word)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                id: addRow
                width: parent.width
                height: 38 * root.s

                readonly property bool lit: addArea.containsMouse || root.focusRowItem === addRow

                HoverHandler {
                    onHoveredChanged: root.reportRowHover(addRow, hovered)
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 5 * root.s
                    anchors.bottomMargin: 5 * root.s
                    radius: 9 * root.s
                    color: addRow.lit ? Qt.alpha(Theme.vermLit, 0.1) : "transparent"
                    border.width: 1
                    border.color: Qt.alpha(Theme.vermLit, addRow.lit ? 0.6 : 0.32)
                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.fast
                        }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6 * root.s

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "+"
                            color: Theme.vermLit
                            font.family: Theme.font
                            font.pixelSize: 14 * root.s
                            font.weight: Font.Bold
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "add word"
                            color: Theme.vermLit
                            font.family: Theme.font
                            font.pixelSize: 11 * root.s
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.5 * root.s
                        }
                    }

                    MouseArea {
                        id: addArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activateRow(addRow)
                    }
                }
            }

            Row {
                width: parent.width

                VocabFileAction {
                    id: importRow
                    page: root
                    width: parent.width / 2
                    label: "Import"
                }
                VocabFileAction {
                    id: exportRow
                    page: root
                    width: parent.width / 2
                    label: "Export"
                    flip: true
                    dim: root.words.length === 0
                }
            }
        }

        // ── word ──

        Column {
            width: parent.width
            visible: root.view === "word" && root.currentEntry !== null
            spacing: 0

            Text {
                width: parent.width
                leftPadding: 9 * root.s
                rightPadding: 9 * root.s
                text: root.current
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 17 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                topPadding: 2 * root.s
                leftPadding: 9 * root.s
                rightPadding: 9 * root.s
                bottomPadding: 6 * root.s
                text: !root.currentEntry || root.currentEntry.heard.length === 0 ? "No forms yet. Teach it so dictation learns how you say it." : "Each line is how the model heard it. Anything that's everyday English is skipped unless you use it, so normal sentences stay as spoken."
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
                lineHeight: 1.2
            }

            Repeater {
                id: formRep
                model: root.currentEntry ? root.currentEntry.heard : []
                onItemAdded: root.rowsRev++
                onItemRemoved: root.rowsRev++

                delegate: Item {
                    id: frow
                    required property int index
                    required property string modelData
                    readonly property string form: frow.modelData

                    readonly property bool focused: root.focusRowItem === frow
                    readonly property bool lit: fhover.hovered || frow.focused
                    readonly property bool risky: {
                        void root.common;
                        return root.isCommon(frow.form);
                    }
                    readonly property bool used: !frow.risky || (root.currentEntry !== null && root.isPinned(root.currentEntry, frow.form))

                    width: parent ? parent.width : 0
                    height: 30 * root.s

                    HoverHandler {
                        id: fhover
                        onHoveredChanged: root.reportRowHover(frow, hovered)
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: 2 * root.s
                        anchors.bottomMargin: 2 * root.s
                        radius: 8 * root.s
                        color: frow.lit ? Theme.frameBg : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: Motion.fast
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: frow.risky ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.activateRow(frow)
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12 * root.s
                        anchors.right: fctl.left
                        anchors.rightMargin: 8 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: "“" + frow.form + "”"
                        color: frow.used ? Theme.cream : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 12 * root.s
                        font.weight: Font.Medium
                        font.strikeout: !frow.used
                        elide: Text.ElideRight
                    }

                    Row {
                        id: fctl
                        anchors.right: parent.right
                        anchors.rightMargin: 6 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4 * root.s

                        /** Everyday-English forms: a chip that reads and flips their state. */
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: frow.risky
                            width: chipText.implicitWidth + 14 * root.s
                            height: 18 * root.s
                            radius: height / 2
                            color: frow.used ? Qt.alpha(Theme.vermLit, 0.14) : Qt.alpha(Theme.flameGlow, chipArea.containsMouse ? 0.2 : 0.12)
                            border.width: 1
                            border.color: frow.used ? Qt.alpha(Theme.vermLit, 0.45) : Qt.alpha(Theme.flameGlow, 0.4)
                            Behavior on color {
                                ColorAnimation {
                                    duration: Motion.fast
                                }
                            }

                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: frow.used ? "used" : "everyday · skipped"
                                color: frow.used ? Theme.vermLit : Theme.flameGlow
                                font.family: Theme.font
                                font.pixelSize: 9 * root.s
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: chipArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activateRow(frow)
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22 * root.s
                            height: 22 * root.s
                            radius: 6 * root.s
                            opacity: frow.lit ? 1 : 0
                            color: frmArea.containsMouse ? Qt.alpha(Theme.verm, 0.16) : "transparent"
                            Behavior on color {
                                ColorAnimation {
                                    duration: Motion.fast
                                }
                            }
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Motion.fast
                                }
                            }

                            GlyphIcon {
                                anchors.centerIn: parent
                                width: 11 * root.s
                                height: 11 * root.s
                                name: "close"
                                color: frmArea.containsMouse ? Theme.vermLit : Theme.iconDim
                                stroke: 2
                            }

                            MouseArea {
                                id: frmArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: frow.lit
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.removeForm(frow.form)
                            }
                        }
                    }
                }
            }

            Item {
                width: 1
                height: 4 * root.s
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.hairSoft
            }

            Item {
                width: 1
                height: 4 * root.s
            }

            Item {
                id: teachMoreRow
                width: parent.width
                height: 30 * root.s
                readonly property bool lit: tmArea.containsMouse || root.focusRowItem === teachMoreRow

                HoverHandler {
                    onHoveredChanged: root.reportRowHover(teachMoreRow, hovered)
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 2 * root.s
                    anchors.bottomMargin: 2 * root.s
                    radius: 8 * root.s
                    color: teachMoreRow.lit ? Theme.frameBg : "transparent"
                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.fast
                        }
                    }
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 9 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 9 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 15 * root.s
                        height: 15 * root.s
                        name: "mic"
                        color: teachMoreRow.lit ? Theme.cream : Theme.subtle
                        stroke: 1.8
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.currentEntry && root.currentEntry.heard.length > 0 ? "Teach more" : "Teach it"
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 12.5 * root.s
                        font.weight: Font.Medium
                    }
                }

                MouseArea {
                    id: tmArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activateRow(teachMoreRow)
                }
            }

            Item {
                id: addAnotherRow
                width: parent.width
                height: 30 * root.s
                readonly property bool lit: aaArea.containsMouse || root.focusRowItem === addAnotherRow

                HoverHandler {
                    onHoveredChanged: root.reportRowHover(addAnotherRow, hovered)
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 2 * root.s
                    anchors.bottomMargin: 2 * root.s
                    radius: 8 * root.s
                    color: addAnotherRow.lit ? Theme.frameBg : "transparent"
                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.fast
                        }
                    }
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 9 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 9 * root.s

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 15 * root.s
                        horizontalAlignment: Text.AlignHCenter
                        text: "+"
                        color: addAnotherRow.lit ? Theme.vermLit : Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 16 * root.s
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Add another word"
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 12.5 * root.s
                        font.weight: Font.Medium
                    }
                }

                MouseArea {
                    id: aaArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activateRow(addAnotherRow)
                }
            }

            Item {
                id: removeWordRow
                width: parent.width
                height: 30 * root.s
                readonly property bool lit: rwArea.containsMouse || root.focusRowItem === removeWordRow

                HoverHandler {
                    onHoveredChanged: root.reportRowHover(removeWordRow, hovered)
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 2 * root.s
                    anchors.bottomMargin: 2 * root.s
                    radius: 8 * root.s
                    color: removeWordRow.lit ? Qt.alpha(Theme.verm, 0.12) : "transparent"
                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.fast
                        }
                    }
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 9 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 9 * root.s

                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 15 * root.s
                        height: 15 * root.s
                        name: "trash"
                        color: removeWordRow.lit ? Theme.vermLit : Theme.subtle
                        stroke: 1.8
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Remove word"
                        color: removeWordRow.lit ? Theme.vermLit : Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 12.5 * root.s
                        font.weight: Font.Medium
                    }
                }

                MouseArea {
                    id: rwArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activateRow(removeWordRow)
                }
            }
        }

        // ── add ──

        Item {
            width: parent.width
            height: visible ? 52 * root.s : 0
            visible: root.view === "add"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 4 * root.s
                anchors.top: parent.top
                anchors.topMargin: 2 * root.s
                text: "WORD"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 8.5 * root.s
                font.weight: Font.Medium
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1 * root.s
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4 * root.s
                height: 28 * root.s
                radius: 8 * root.s
                color: Theme.frameBg
                border.width: 1
                border.color: root.addWarn ? Qt.alpha(Theme.flameGlow, 0.55) : (addField.activeFocus ? Qt.alpha(Theme.vermLit, 0.45) : Theme.hairSoft)
                Behavior on border.color {
                    ColorAnimation {
                        duration: Motion.fast
                    }
                }

                TextField {
                    id: addField
                    anchors.left: parent.left
                    anchors.leftMargin: 11 * root.s
                    anchors.right: parent.right
                    anchors.rightMargin: 11 * root.s
                    anchors.verticalCenter: parent.verticalCenter
                    background: null
                    padding: 0
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    placeholderText: "Spelled exactly as it should be typed"
                    placeholderTextColor: Theme.faint
                    selectByMouse: true
                    selectionColor: Theme.verm
                    text: root.addText
                    onTextEdited: {
                        root.addText = text;
                        root.addWarn = false;
                    }
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Escape) {
                            root.toList();
                            e.accepted = true;
                        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            root.submitAdd();
                            e.accepted = true;
                        }
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: root.view === "add" && root.addWarn
            topPadding: 2 * root.s
            bottomPadding: 6 * root.s
            leftPadding: 4 * root.s
            rightPadding: 4 * root.s
            text: "“" + root.addText.trim() + "” is everyday English, so the model already knows it and should spell it right on its own. Press Enter again to add it anyway."
            color: Theme.flameGlow
            font.family: Theme.font
            font.pixelSize: 10 * root.s
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
            lineHeight: 1.2
        }

        // ── teach ──

        Column {
            width: parent.width
            visible: root.view === "teach"
            spacing: 0

            Text {
                width: parent.width
                topPadding: 6 * root.s
                horizontalAlignment: Text.AlignHCenter
                text: root.current
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 20 * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                topPadding: 4 * root.s
                horizontalAlignment: Text.AlignHCenter
                text: Dictate.live ? "Listening…" : (Dictate.state === "working" ? "Working it out…" : (root.teachTakes >= root.goal ? "Got it" : (root.teachTakes === 0 ? "Hold " + Dictate.keyLabel + " and say it" : "Once more")))
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 11 * root.s
                font.weight: Font.Medium
            }

            DictateBars {
                width: parent.width
                height: 34 * root.s
                s: root.s
                idle: true
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 7 * root.s

                Repeater {
                    model: root.goal

                    Rectangle {
                        required property int index
                        readonly property bool filled: index < root.teachTakes
                        width: 6 * root.s
                        height: 6 * root.s
                        radius: width / 2
                        color: filled ? Theme.vermLit : "transparent"
                        border.width: 1
                        border.color: filled ? Theme.vermLit : Theme.hair
                        scale: filled ? 1 : 0.85
                        Behavior on color {
                            ColorAnimation {
                                duration: Motion.fast
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: Motion.standard
                                easing.type: Easing.OutBack
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                topPadding: 10 * root.s
                leftPadding: 9 * root.s
                rightPadding: 9 * root.s
                horizontalAlignment: Text.AlignHCenter
                visible: root.lastHeard.length > 0 || !Dictate.ready
                readonly property bool risky: {
                    void root.common;
                    return root.lastHeard.length > 0 && root.isCommon(root.lastHeard);
                }
                text: !Dictate.ready ? "Speech model is loading…" : "Heard “" + root.lastHeard + "”" + (risky ? ". That's everyday English, so it'll be skipped unless you use it" : "")
                color: risky ? Theme.flameGlow : Theme.faint
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }

            Item {
                width: 1
                height: 8 * root.s
            }
        }

        Item {
            width: 1
            height: 6 * root.s
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hairSoft
        }

        Item {
            width: parent.width
            height: 20 * root.s

            Hint {
                anchors.left: parent.left
                anchors.leftMargin: 4 * root.s
                anchors.verticalCenter: parent.verticalCenter
                text: root.view === "teach" ? "enter save · esc back" : (root.view === "add" ? "enter next · esc back" : (root.view === "word" ? "enter use / skip · del remove form · esc back" : (searchField.activeFocus ? "↑↓ pick · enter open · esc clear" : "type to search · enter open · del remove · esc close")))
            }
        }
    }
}
