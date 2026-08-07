import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const fixturePath = resolve(root, 'docs/fixtures/code-normalization.json');
const outputPath = resolve(root, 'supabase/tests/generated_normalization_values.sql');
const includePath = resolve(root, 'supabase/tests/generated_normalization_values.sql.in');
const fixture = JSON.parse(readFileSync(fixturePath, 'utf8'));
const alphabet = /^[0-9A-HJKMNP-TV-Z]$/u;

function normalize(value) {
  return [...value.toUpperCase()]
    .map((character) => ({ I: '1', L: '1', O: '0', U: '1' })[character] ?? character)
    .filter((character) => alphabet.test(character))
    .join('');
}

function hash(value) {
  return createHash('sha256').update(value).digest('hex');
}

for (const entry of fixture.entries) {
  const normalized = normalize(entry.input);
  if (normalized !== entry.normalized || hash(normalized) !== entry.sha256) {
    throw new Error(`Normalization fixture mismatch for ${JSON.stringify(entry.input)}`);
  }
}

const canonical = JSON.stringify(fixture);
const checksum = hash(canonical);
const sqlLiteral = (value) => `'${value.replaceAll("'", "''")}'`;
const values = fixture.entries
  .map(
    (entry) =>
      `  (${sqlLiteral(entry.input)}, ${sqlLiteral(entry.normalized)}, ${sqlLiteral(entry.sha256)})`,
  )
  .join(',\n');

const output = `-- GENERATED FILE. Do not edit by hand.\n-- fixture-sha256: ${checksum}\nbegin;\nselect plan(0);\ncreate temporary table normalization_fixture_values (\n  input text not null,\n  normalized text not null,\n  sha256 text not null\n);\ninsert into normalization_fixture_values (input, normalized, sha256)\nvalues\n${values};\nrollback;\n`;
writeFileSync(outputPath, output, 'utf8');
writeFileSync(
  includePath,
  `-- GENERATED INSERT. Do not edit by hand.\ninsert into fixture (input, normalized, sha256)\nvalues\n${values};\n`,
  'utf8',
);
console.log(`Wrote ${outputPath} (${fixture.entries.length} rows, checksum ${checksum})`);
