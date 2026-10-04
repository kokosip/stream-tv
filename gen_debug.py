
const fs = require('fs');
let common = fs.readFileSync('kisskh_common.js', 'utf8');

// Replace the return function line to console.log _0x5989e7
common = common.replace("const _0x278f64=", "console.log('ARRAY:', JSON.stringify(_0x5989e7)); const _0x278f64=");

fs.writeFileSync('test_debug_array.js', common + `
const fn = _0x54b991;
const token = fn(147731, null, "2.8.10", "62f176f3bb1b5b8e70e39932ad34a0c7", 4830201, "kisskh", "kisskh", "kisskh", "kisskh", "kisskh", "kisskh");
console.log('TOKEN:', token);
`);
