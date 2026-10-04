
const fs = require('fs');
let common = fs.readFileSync('kisskh_common.js', 'utf8');

// Monkey patch in common
common = common.replace(
    'const _0x278f64=_0x29e11d(_0x5989e7[_0x5acc2f(0x124)](\'|\'))',
    'console.log("Joined before pad:", _0x5989e7[_0x5acc2f(0x124)]("|")); const _0x278f64=_0x29e11d(_0x5989e7[_0x5acc2f(0x124)]("|")); console.log("Padded len:", _0x278f64.length);'
);

const fn = new Function('context', common + '; return _0x54b991;');
const generator = fn({});
generator(147731, null, "2.8.10", "62f176f3bb1b5b8e70e39932ad34a0c7", 4830201, "kisskh", "kisskh", "kisskh", "kisskh", "kisskh", "kisskh");
