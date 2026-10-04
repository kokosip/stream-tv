
const fs = require('fs');
const common = fs.readFileSync('kisskh_common.js', 'utf8');

// We can check how the key expansion is initialized in common.js
console.log("Reading key schedule...");
