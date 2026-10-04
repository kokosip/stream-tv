
const fs = require('fs');
const common = fs.readFileSync('kisskh_common.js', 'utf8');

// evaluate common.js
const context = {};
const fn = new Function('context', common + '; return _0x54b991;');
const generator = fn(context);

const episodeId = 225823;
const uid = "62f176f3bb1b5b8e70e39932ad34a0c7";
const token = generator(episodeId, null, "2.8.10", uid, 4830201, "kisskh", "kisskh", "kisskh", "kisskh", "kisskh", "kisskh");
console.log("Generated token:", token);
