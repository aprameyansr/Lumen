function fieldMatch(text, name) {
    const prefix = "(\\b" + escapeRe(name) + "\\s*=\\s*)";
    return new RegExp(prefix + '("(?:\\\\.|[^"\\\\])*"|[^,}\\r\\n]*)').exec(text);
}

function getField(text, name) {
    const match = fieldMatch(text, name);
    if (!match)
        return "";
    const value = match[2].trim();
    return value.length >= 2 && value.startsWith('"') && value.endsWith('"') ? value.slice(1, -1) : value;
}

// The caller supplies a Lua literal. Preserve the spacing around the old value.
function setField(text, name, valueLiteral) {
    const match = fieldMatch(text, name);
    if (!match)
        return {
            text: text,
            ok: false
        };
    const trailingSpace = match[2].match(/[ \t]*$/)[0];
    const end = match.index + match[0].length;
    return {
        text: text.slice(0, match.index) + match[1] + valueLiteral + trailingSpace + text.slice(end),
        ok: true
    };
}

function closingBrace(text, start) {
    let depth = 1;
    for (let index = start + 1; index < text.length; index++) {
        const char = text[index];
        if (char === "{")
            depth++;
        else if (char === "}" && --depth === 0)
            return index;
    }
    return -1;
}

// Return the range and contents between the braces of a named table.
function getBlock(text, blockName) {
    const match = new RegExp("\\b" + escapeRe(blockName) + "\\s*=\\s*\\{").exec(text);
    if (!match)
        return null;
    const start = match.index + match[0].length;
    const end = closingBrace(text, start - 1);
    return end < 0 ? null : {
        start: start,
        end: end,
        body: text.slice(start, end)
    };
}

/**
 * Reads a `name = <value>` field scoped to `blockName`'s body. Returns "" when
 * the block or the field within it is absent.
 */
function getBlockField(text, blockName, name) {
    const blk = getBlock(text, blockName);
    if (!blk)
        return "";
    return getField(blk.body, name);
}

/**
 * Rewrites a `name = <value>` field scoped to `blockName`'s body and splices the
 * block back into the whole text. Scoping keeps a name shared by sibling blocks
 * (e.g. `enabled` in both shadow and blur) from matching the wrong block.
 * Returns `{ text, ok }`; ok is false (text unchanged) when the block or field
 * is absent.
 */
function setBlockField(text, blockName, name, valueLiteral) {
    const blk = getBlock(text, blockName);
    if (!blk)
        return {
            text: text,
            ok: false
        };
    const res = setField(blk.body, name, valueLiteral);
    if (!res.ok)
        return {
            text: text,
            ok: false
        };
    return {
        text: text.slice(0, blk.start) + res.text + text.slice(blk.end),
        ok: true
    };
}

function escapeRe(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Finds the bounds of the `hl.layer_rule({ ... })` call whose body carries
 * `name = "ruleName"`. Walks each `hl.layer_rule(` head, brace-balances to its
 * matching `})`, and returns `{ start, end }` (from the head to just past the
 * close) for the first call that names `ruleName`. Returns null when no such
 * call exists.
 */
function findNamedRule(text, ruleName) {
    const head = /hl\.layer_rule\s*\(\s*\{/g;
    const name = new RegExp('\\bname\\s*=\\s*"' + escapeRe(ruleName) + '"');
    let match;
    while ((match = head.exec(text)) !== null) {
        const brace = closingBrace(text, head.lastIndex - 1);
        if (brace < 0)
            continue;
        const parenthesis = text.indexOf(")", brace);
        const end = (parenthesis < 0 ? brace : parenthesis) + 1;
        if (name.test(text.slice(match.index, end)))
            return {
                start: match.index,
                end: end
            };
    }
    return null;
}

/**
 * Reports whether an `hl.layer_rule` call named `ruleName` is present.
 */
function hasNamedRule(text, ruleName) {
    return findNamedRule(text, ruleName) !== null;
}

/**
 * Removes the whole `hl.layer_rule({ ... })` call named `ruleName`, together
 * with one trailing newline and the single blank line `addNamedRule` puts in
 * front of an appended rule, leaving the rest of the file byte-identical.
 * Returns `{ text, ok }`; ok is false (text unchanged) when no such rule exists.
 */
function removeNamedRule(text, ruleName) {
    const r = findNamedRule(text, ruleName);
    if (!r)
        return {
            text: text,
            ok: false
        };
    let start = r.start;
    if (text.charAt(start - 1) === "\n" && text.charAt(start - 2) === "\n")
        start--;
    let end = r.end;
    if (text.charAt(end) === "\n")
        end++;
    return {
        text: text.slice(0, start) + text.slice(end),
        ok: true
    };
}

/**
 * Appends `block` (a complete `hl.layer_rule({...})` string) at the end of the
 * file, separated by a blank line, unless that exact block is already present.
 * Returns `{ text, ok }`; ok is false (text unchanged) when the block already
 * exists.
 */
function addNamedRule(text, block) {
    if (text.indexOf(block) !== -1)
        return {
            text: text,
            ok: false
        };
    const sep = text.length === 0 || text.charAt(text.length - 1) === "\n" ? "\n" : "\n\n";
    return {
        text: text + sep + block,
        ok: true
    };
}

/**
 * Replaces the second argument of a `hl.env("KEY", "<old>")` call with the raw
 * value, re-quoted. Returns `{ text, ok }`; ok is false when the key's env call is
 * absent.
 */
function setEnv(text, key, valueRaw) {
    const re = new RegExp("(hl\\.env\\(\\s*\"" + escapeRe(key) + "\"\\s*,\\s*)\"[^\"]*\"");
    if (!re.test(text))
        return {
            text: text,
            ok: false
        };
    return {
        text: text.replace(re, (_, prefix) => prefix + '"' + valueRaw + '"'),
        ok: true
    };
}

/**
 * Reads the value of an `hl.env("KEY", "value")` line, the read side of setEnv.
 * Returns "" when the key is absent.
 */
function getEnv(text, key) {
    const re = new RegExp("hl\\.env\\(\\s*\"" + escapeRe(key) + "\"\\s*,\\s*\"([^\"]*)\"");
    const m = re.exec(text);
    return m ? m[1] : "";
}

/**
 * Replaces the theme name and size in a `hyprctl setcursor <theme> <size>` call.
 * Returns `{ text, ok }`; ok is false when the call is absent.
 */
function setCursorLine(text, theme, size) {
    const re = /setcursor\s+\S+\s+\d+/;
    if (!re.test(text))
        return {
            text: text,
            ok: false
        };
    return {
        text: text.replace(re, () => "setcursor " + theme + " " + size),
        ok: true
    };
}
