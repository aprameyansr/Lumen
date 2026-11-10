/**
 * Safe arithmetic evaluator for the launcher's calc mode. A hand written
 * recursive descent parser walks a small grammar, so a typed query never reaches
 * a JS eval and can never run code.
 *
 *   operators   + - * / ^ and postfix % (divide by 100), parentheses, decimals
 *   spellings   x × · for *, ÷ for /, − for -, ** for ^
 *   constants   pi (π), e, tau, ans (the caller's previous answer)
 *   functions   sqrt (√), cbrt, abs, sin, cos, tan, asin, acos, atan (radians),
 *               ln, log (base 10), log2, exp, floor, ceil, round; written as
 *               sqrt(2), sqrt 2 or √2
 *   implicit *  a number or ")" directly before "(" or a name: 2pi, 3(4+1), 2√9
 *
 * evaluate(src, ans) returns { ok, value, display, ops } where `ops` counts real
 * operations (function calls and implicit products included), letting the
 * launcher show a result only when the query is an actual calculation and not a
 * lone number, a lone constant or an app name. Any unknown word fails the parse,
 * so queries like python3, i3 or e-mail fall through to app search.
 */

var CONSTANTS = { pi: Math.PI, e: Math.E, tau: 2 * Math.PI };

var FUNCTIONS = {
    sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs,
    sin: Math.sin, cos: Math.cos, tan: Math.tan,
    asin: Math.asin, acos: Math.acos, atan: Math.atan,
    ln: Math.log, log: Math.log10, log2: Math.log2, exp: Math.exp,
    floor: Math.floor, ceil: Math.ceil, round: Math.round
};

/** Single-character spellings mapped onto the core token set. */
var ALIASES = {
    '×': '*',   // ×
    '·': '*',   // ·
    '÷': '/',   // ÷
    '−': '-'    // −
};

function isDigit(c) { return c >= '0' && c <= '9'; }
function isLetter(c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }

function tokenize(src) {
    var tokens = [];
    var i = 0;
    while (i < src.length) {
        var c = src[i];
        if (c === ' ' || c === '\t') { i++; continue; }
        if (isDigit(c) || c === '.') {
            var j = i, dots = 0;
            while (j < src.length && (isDigit(src[j]) || src[j] === '.')) {
                if (src[j] === '.') dots++;
                j++;
            }
            if (dots > 1) return null;
            tokens.push({ t: 'num', v: parseFloat(src.slice(i, j)) });
            i = j;
            continue;
        }
        if (isLetter(c)) {
            var k = i;
            while (k < src.length && isLetter(src[k])) k++;
            var word = src.slice(i, k).toLowerCase();
            // log2 is the one name with a digit; "log 2" and "log20" stay base 10.
            if (word === 'log' && src[k] === '2' && !(isDigit(src[k + 1]) || src[k + 1] === '.')) {
                word = 'log2';
                k++;
            }
            tokens.push(word === 'x' ? { t: '*' } : { t: 'id', v: word });
            i = k;
            continue;
        }
        if (c === '*' && src[i + 1] === '*') {
            tokens.push({ t: '^' });
            i += 2;
            continue;
        }
        if (c === 'π') { tokens.push({ t: 'id', v: 'pi' }); i++; continue; }    // π
        if (c === '√') { tokens.push({ t: 'id', v: 'sqrt' }); i++; continue; }  // √
        if (ALIASES[c]) { tokens.push({ t: ALIASES[c] }); i++; continue; }
        if ('+-*/^%()'.indexOf(c) >= 0) {
            tokens.push({ t: c });
            i++;
            continue;
        }
        return null;
    }
    return tokens;
}

function evaluate(src, ans) {
    var fail = { ok: false, value: NaN, display: "", ops: 0 };
    if (!src || !src.trim()) return fail;
    var tokens = tokenize(src);
    if (!tokens || tokens.length === 0) return fail;

    var hasAns = typeof ans === 'number' && isFinite(ans);
    var pos = 0;
    var ops = 0;

    function peek() { return tokens[pos]; }

    /** True when the next token starts an implicit product with what came just before it. */
    function implicitNext() {
        var prev = tokens[pos - 1];
        var next = tokens[pos];
        if (!prev || !next) return false;
        if (prev.t !== 'num' && prev.t !== ')') return false;
        return next.t === '(' || next.t === 'id';
    }

    function parseExpr() {
        var v = parseTerm();
        for (;;) {
            var tok = peek();
            if (tok && tok.t === '+') { pos++; v = v + parseTerm(); ops++; }
            else if (tok && tok.t === '-') { pos++; v = v - parseTerm(); ops++; }
            else break;
        }
        return v;
    }
    function parseTerm() {
        var v = parsePower();
        for (;;) {
            var tok = peek();
            if (tok && tok.t === '*') { pos++; v = v * parsePower(); ops++; }
            else if (tok && tok.t === '/') { pos++; v = v / parsePower(); ops++; }
            else if (implicitNext()) { v = v * parsePower(); ops++; }
            else break;
        }
        return v;
    }
    function parsePower() {
        var base = parseUnary();
        var tok = peek();
        if (tok && tok.t === '^') { pos++; ops++; return Math.pow(base, parsePower()); }
        return base;
    }
    function parseUnary() {
        var tok = peek();
        if (tok && tok.t === '-') { pos++; return -parseUnary(); }
        if (tok && tok.t === '+') { pos++; return parseUnary(); }
        return parsePostfix();
    }
    function parsePostfix() {
        var v = parsePrimary();
        var tok = peek();
        if (tok && tok.t === '%') { pos++; ops++; v = v / 100; }
        return v;
    }
    function parsePrimary() {
        var tok = peek();
        if (!tok) throw "eof";
        if (tok.t === 'num') { pos++; return tok.v; }
        if (tok.t === '(') {
            pos++;
            var v = parseExpr();
            if (!(peek() && peek().t === ')')) throw "paren";
            pos++;
            return v;
        }
        if (tok.t === 'id') {
            pos++;
            if (tok.v === 'ans') {
                if (!hasAns) throw "noans";
                return ans;
            }
            if (Object.prototype.hasOwnProperty.call(CONSTANTS, tok.v))
                return CONSTANTS[tok.v];
            if (Object.prototype.hasOwnProperty.call(FUNCTIONS, tok.v)) {
                var arg = parseUnary();
                ops++;
                return FUNCTIONS[tok.v](arg);
            }
            throw "unknown";
        }
        throw "unexpected";
    }

    var value;
    try {
        value = parseExpr();
    } catch (e) {
        return fail;
    }
    if (pos !== tokens.length) return fail;
    if (typeof value !== 'number' || !isFinite(value)) return fail;
    if (ops < 1) return fail;

    var rounded = parseFloat(value.toPrecision(12));
    if (rounded === 0) rounded = 0;
    return { ok: true, value: rounded, display: String(rounded), ops: ops };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { evaluate };
}
