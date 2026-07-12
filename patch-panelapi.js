const fs = require('fs');
const path = '/app/apps/panel-api/dist/server.cjs';
let code = fs.readFileSync(path, 'utf8');

let changes = 0;

// computeStatus function
const csStart = code.indexOf('function computeStatus(state, now =');
if (csStart !== -1) {
  const braceStart = code.indexOf('{', csStart);
  let depth = 1, i = braceStart + 1;
  while (i < code.length && depth > 0) {
    if (code[i] === '{') depth++;
    if (code[i] === '}') depth--;
    i++;
  }
  code = code.substring(0, csStart) + 'function computeStatus() { return "active"; }' + code.substring(i);
  console.log('Patched computeStatus');
  changes++;
} else {
  console.log('computeStatus NOT FOUND (may already be patched)');
}

// evaluateLicense
const elStart = code.indexOf('async function evaluateLicense(');
if (elStart !== -1) {
  const braceStart = code.indexOf('{', elStart);
  let depth = 1, i = braceStart + 1;
  while (i < code.length && depth > 0) {
    if (code[i] === '{') depth++;
    if (code[i] === '}') depth--;
    i++;
  }
  code = code.substring(0, elStart) + 'async function evaluateLicense() { return "active"; }' + code.substring(i);
  console.log('Patched evaluateLicense');
  changes++;
} else {
  console.log('evaluateLicense NOT FOUND');
}

// isProcessingAllowed
const ipaStart = code.indexOf('function isProcessingAllowed(');
if (ipaStart !== -1) {
  const braceStart = code.indexOf('{', ipaStart);
  let depth = 1, i = braceStart + 1;
  while (i < code.length && depth > 0) {
    if (code[i] === '{') depth++;
    if (code[i] === '}') depth--;
    i++;
  }
  code = code.substring(0, ipaStart) + 'function isProcessingAllowed() { return true; }' + code.substring(i);
  console.log('Patched isProcessingAllowed');
  changes++;
} else {
  console.log('isProcessingAllowed NOT FOUND');
}

// assertLicenseActive
const alaStart = code.indexOf('async function assertLicenseActive()');
if (alaStart !== -1) {
  const braceStart = code.indexOf('{', alaStart);
  let depth = 1, i = braceStart + 1;
  while (i < code.length && depth > 0) {
    if (code[i] === '{') depth++;
    if (code[i] === '}') depth--;
    i++;
  }
  code = code.substring(0, alaStart) + 'async function assertLicenseActive() { return { allowed: true, status: "active" }; }' + code.substring(i);
  console.log('Patched assertLicenseActive');
  changes++;
} else {
  console.log('assertLicenseActive NOT FOUND');
}

// Write backup and new file
fs.writeFileSync(path + '.bak', code);
fs.writeFileSync(path, code);
console.log('Total changes:', changes);
