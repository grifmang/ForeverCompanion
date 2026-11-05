// Static parsing only. Addon Lua is never executed or supplied a mocked WoW runtime.
'use strict';
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');
const expected = [
  'Core.lua', 'API.lua', 'Store.lua', 'UI/Widgets.lua', 'UI/Shell.lua',
  'Modules/PriceAPI.lua', 'Modules/Wallet.lua', 'Modules/RecipeAPI.lua',
  'Modules/Crafting.lua', 'Modules/Items.lua', 'Modules/LegacyAPI.lua',
  'Modules/Legacy.lua', 'Modules/QuestTracker.lua', 'Modules/QuestSync.lua',
  'Modules/QuestLogUI.lua', 'Modules/ObjectiveTrackerUI.lua',
  'Modules/Adventure.lua', 'Modules/Updates.lua', 'Modules/PartyProtocol.lua', 'Startup.lua'
];

function fail(message) { throw new Error(message); }
function regularFile(root, relative) {
  if (!expected.includes(relative)) fail(`Unapproved Lua path: ${relative}`);
  let current = root;
  for (const part of relative.split('/')) {
    current = path.join(current, part);
    const stat = fs.lstatSync(current);
    if (stat.isSymbolicLink()) fail(`Linked input is forbidden: ${relative}`);
  }
  if (!fs.statSync(current).isFile()) fail(`Lua input is not a file: ${relative}`);
  return current;
}

try {
  const args = process.argv.slice(2);
  if (args.length && (args.length !== 2 || args[0] !== '--root')) fail('Usage: node Tools/check-lua.cjs [--root addon-directory]');
  const root = path.resolve(args[1] || path.join(__dirname, '..'));
  if (fs.lstatSync(root).isSymbolicLink()) fail('Addon root must not be a symlink.');
  const tocNames = ['ForeverCompanion.toc', 'ForeverCompanion_Camelot.toc'];
  const tocs = tocNames.map(name => {
    const file = path.join(root, name);
    if (fs.lstatSync(file).isSymbolicLink()) fail(`Linked TOC: ${name}`);
    return fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '').replace(/\r\n/g, '\n');
  });
  if (tocs[0] !== tocs[1]) fail('Flavor TOCs differ.');
  const entries = tocs[0].split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('#'));
  if (entries.length !== expected.length || entries.some((entry, index) => entry !== expected[index])) fail('TOC runtime paths or order differ from the 20-file allowlist.');
  const versions = [...tocs[0].matchAll(/^## Version: ([^\r\n]+)$/gm)];
  if (versions.length !== 1 || !/^\d+\.\d+\.\d+-prototype(?:\.[1-9]\d{0,6})?$/.test(versions[0][1])) fail('Missing or invalid prototype TOC version.');
  const core = fs.readFileSync(regularFile(root, 'Core.lua'), 'utf8').replace(/^\uFEFF/, '');
  const coreVersions = [...core.matchAll(/FC\.name,\s*FC\.version\s*=\s*addonName,\s*"([^"]+)"/g)];
  if (coreVersions.length !== 1 || coreVersions[0][1] !== versions[0][1]) fail('Core and TOC versions differ.');
  let failures = 0;
  for (const relative of entries) {
    try {
      const source = fs.readFileSync(regularFile(root, relative), 'utf8').replace(/^\uFEFF/, '');
      luaparse.parse(source, {luaVersion: '5.1', locations: true});
    } catch (error) {
      failures++;
      process.stderr.write(`${relative}: ${error.message}\n`);
    }
  }
  process.stdout.write(`Lua 5.1 static parsing: ${entries.length} allowlisted files, ${failures} failures; version ${versions[0][1]}.\n`);
  process.exitCode = failures ? 1 : 0;
} catch (error) {
  process.stderr.write(`Static check failed: ${error.message}\n`);
  process.exitCode = 1;
}
