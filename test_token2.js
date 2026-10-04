
const fs = require('fs');
const common = fs.readFileSync('kisskh_common.js', 'utf8');
const fn = new Function('context', common + '; return _0x54b991;');
const generator = fn({});
const token = generator(147731, null, "2.8.10", "62f176f3bb1b5b8e70e39932ad34a0c7", 4830201, "kisskh", "kisskh", "kisskh", "kisskh", "kisskh", "kisskh");
console.log(token);
