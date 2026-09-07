/** Extract a code only from the backend's plain-text verification template.
 * The caller verifies recipient and arrival time before passing MIME source.
 * Neither the source nor the code belongs in acceptance evidence.
 */
export function extractEmailCode(source) {
  const message = Buffer.isBuffer(source) ? source.toString('utf8') : String(source);
  const candidates = [message];
  for (const part of message.split(/\r?\n--[^\r\n]+\r?\n/u)) {
    const split = part.search(/\r?\n\r?\n/u);
    if (split < 0) continue;
    const headers = part.slice(0, split);
    const body = part.slice(split).trim();
    if (/Content-Transfer-Encoding:\s*base64/iu.test(headers)) {
      candidates.push(Buffer.from(body.replace(/\s/gu, ''), 'base64').toString('utf8'));
    } else if (/Content-Transfer-Encoding:\s*quoted-printable/iu.test(headers)) {
      candidates.push(body.replace(/=\r?\n/gu, '').replace(/=([0-9a-f]{2})/giu, (_, hex) =>
        String.fromCharCode(Number.parseInt(hex, 16))));
    }
  }
  const codes = new Set(candidates.flatMap((candidate) =>
    [...candidate.matchAll(/Your verification code is:\s*([0-9]{8})(?![0-9])/gu)]
      .map((match) => match[1])));
  if (codes.size !== 1) throw new Error('The mailbox message did not contain one valid verification code.');
  return [...codes][0];
}

export function isUuid(value) {
  return typeof value === 'string'
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(value);
}

export function redactSensitiveText(input, sensitiveValues = []) {
  let message = String(input);
  for (const value of [...sensitiveValues]
    .filter((entry) => typeof entry === 'string' && entry.length >= 4)
    .sort((left, right) => right.length - left.length)) {
    message = message.replaceAll(value, '[redacted]');
  }
  return message.replace(/("?(?:code|bindingToken|csrfToken|refreshToken|accessToken)"?\s*[:=]\s*)[^\s,}]+/giu, '$1[redacted]');
}
