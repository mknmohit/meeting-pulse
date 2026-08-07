const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const ALPHABET_SET = new Set(ALPHABET);

export function normalizePairingCode(value: string): string {
  const mapped = value
    .toUpperCase()
    .replaceAll('I', '1')
    .replaceAll('L', '1')
    .replaceAll('O', '0')
    .replaceAll('U', '1');
  return [...mapped]
    .filter((character) => ALPHABET_SET.has(character))
    .join('');
}

export function isPairingCode(value: string): boolean {
  return normalizePairingCode(value).length === 10;
}
