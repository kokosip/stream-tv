
const parts = ['', 147731, null, 'mg3c3b04ba', '2.8.10', '62f176f3bb1b5b8e70e39932ad34a0c7', 4830201, 'kisskh', 'kisskh', 'kisskh', 'kisskh', 'kisskh', 'kisskh', '00', ''];
const s = parts.join('|');
let h = 0;
for (let i = 0; i < s.length; i++) {
    const prev = h;
    const shifted = (h << 5);
    const charCode = s.charCodeAt(i);
    h = shifted - h + charCode;
    if (i < 5 || i > s.length - 5) {
        console.log(`i=${i} char=${s[i]} prev=${prev} shifted=${shifted} h=${h}`);
    }
}
