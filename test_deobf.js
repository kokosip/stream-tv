
const fs = require('fs');
const common = fs.readFileSync('kisskh_common.js', 'utf8');

// evaluate to get _0x3a8d
const fn = new Function('let ret;' + common + '; return _0x3a8d;');
const _0x3a8d = fn();

const indices = [0x10b, 0x10e, 0x10f, 0x110, 0x111, 0x112, 0x114, 0x115, 0x117, 0x118, 0x119, 0x11c, 0x11e, 0x11f, 0x120, 0x121, 0x122, 0x124];
for (const i of indices) {
    try {
        console.log(`0x${i.toString(16)}: ${_0x3a8d(i)}`);
    } catch (e) {
        console.log(`0x${i.toString(16)}: err`);
    }
}
