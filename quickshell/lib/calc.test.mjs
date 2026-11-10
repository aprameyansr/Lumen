import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { evaluate } = require("./calc.js");

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}

function val(src, ans) {
    const r = evaluate(src, ans);
    return r.ok ? r.value : "fail";
}

// Existing behaviour
eq(val("1+2"), 3, "1+2");
eq(val("2^3^2"), 512, "power is right associative");
eq(val("50%"), 0.5, "postfix percent");
eq(val("-(2+3)*4"), -20, "unary minus over parens");
eq(val("0.1+0.2"), 0.3, "rounded display");
eq(val("5"), "fail", "lone number");
eq(val("1..2"), "fail", "double dot");
eq(val("1/0"), "fail", "division by zero");

// Functions and constants
eq(val("sqrt(16)"), 4, "sqrt(16)");
eq(val("sqrt 16"), 4, "sqrt without parens");
eq(val("√2*√2"), 2, "√ prefix");
eq(val("2√9"), 6, "implicit product with √");
eq(val("2pi"), 6.28318530718, "2pi");
eq(val("2π"), 6.28318530718, "2π");
eq(val("sin(pi/2)"), 1, "sin(pi/2)");
eq(val("cos(0)"), 1, "cos(0)");
eq(val("ln(e)"), 1, "ln(e)");
eq(val("log(1000)"), 3, "log is base 10");
eq(val("log2(8)"), 3, "log2(8)");
eq(val("log 100"), 2, "log with a space");
eq(val("log20*1"), 1.30102999566, "log20 is log(20)");
eq(val("abs(-4)"), 4, "abs");
eq(val("PI*2"), 6.28318530718, "names are case insensitive");
eq(val("tau/2"), 3.14159265359, "tau");

// Spellings
eq(val("3x4"), 12, "x as multiply");
eq(val("3 x 4"), 12, "spaced x");
eq(val("3×4"), 12, "×");
eq(val("6÷4"), 1.5, "÷");
eq(val("5−2"), 3, "unicode minus");
eq(val("2**10"), 1024, "** as power");
eq(val("3(4+1)"), 15, "implicit product with parens");
eq(val("(1+1)(2+2)"), 8, "paren times paren");

// ans
eq(val("ans*2", 21), 42, "ans with a previous answer");
eq(val("ans+1"), "fail", "ans with no previous answer");
eq(val("ans+1", NaN), "fail", "ans when NaN");
eq(val("ans", 5), "fail", "lone ans is not a calculation");

// App names must fall through to app search
for (const q of ["python3", "i3", "firefox", "e-mail", "pi-hole", "pi", "e", "x", "sqrt", "2x", "log", "xterm", "exp"])
    eq(val(q), "fail", "app guard: " + q);

console.log(failed ? `\n${failed} failed` : "\nall passed");
process.exit(failed ? 1 : 0);
