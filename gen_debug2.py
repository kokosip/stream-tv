
const fs = require('fs');
let common = fs.readFileSync('kisskh_common.js', 'utf8');

// intercept _3505d7 to log after first round
common = common.replace(
    "return function(_0x3be93d",
    "global.dbg_words = []; return function(_0x3be93d"
);

// We can just log _0x6b7b62
fs.writeFileSync('test_debug_tables.js', common + `
const fn = _0x54b991;
fn(147731, null, "2.8.10", "62f176f3bb1b5b8e70e39932ad34a0c7", 4830201, "kisskh", "kisskh", "kisskh", "kisskh", "kisskh", "kisskh");
`);
