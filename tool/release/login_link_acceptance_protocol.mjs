import {createHash, randomBytes, randomUUID} from 'node:crypto';

const BASE64URL_256 = /^[A-Za-z0-9_-]{43}$/u;
const APPROVAL_CAPABILITY = /^[A-Za-z0-9_-]{40,128}$/u;

/**
 * Creates the private proof material owned by one synthetic originating client.
 * Callers must never log or persist the returned poll token, verifier, or state.
 */
export function createLoginLinkProof() {
  const pollToken = randomBytes(32).toString('base64url');
  const codeVerifier = randomBytes(32).toString('base64url');
  const state = randomBytes(32).toString('base64url');

  return {
    requestId: randomUUID(),
    installationId: randomUUID(),
    pollToken,
    pollChallenge: sha256Base64Url(pollToken),
    codeVerifier,
    codeChallenge: sha256Base64Url(codeVerifier),
    state,
  };
}

/**
 * Extracts only the scanner-safe fragment link for the exact request. Error
 * messages deliberately exclude message content and approval capabilities.
 */
export function extractApprovalLink(source, requestId, expectedOrigin) {
  if (!isUuid(requestId)) {
    throw new Error('The login-link request identifier is invalid.');
  }
  let trustedOrigin;
  try {
    const configured = new URL(expectedOrigin);
    if (configured.protocol !== 'https:') throw new Error('HTTPS is required.');
    trustedOrigin = configured.origin;
  } catch {
    throw new Error('The configured login approval origin is invalid.');
  }

  const message = Buffer.isBuffer(source) ? source.toString('utf8') : String(source);
  const expectedPath = `/login-links/${requestId.toLowerCase()}`;
  const candidates = message.match(/https:\/\/[^\s<>"']+/gu) ?? [];

  for (const candidate of candidates) {
    let link;
    try {
      link = new URL(trimTerminalPunctuation(candidate));
    } catch {
      continue;
    }
    if (
      link.protocol !== 'https:'
      || link.origin !== trustedOrigin
      || link.pathname.toLowerCase() !== expectedPath
      || link.search !== ''
    ) {
      continue;
    }
    const fragment = new URLSearchParams(link.hash.slice(1));
    const approval = fragment.get('approval') ?? '';
    if (fragment.size !== 1 || !APPROVAL_CAPABILITY.test(approval)) {
      continue;
    }
    return link.href;
  }

  throw new Error('The matching mailbox message did not contain a valid login approval link.');
}

export function isLoginLinkProofShape(proof) {
  return isUuid(proof?.requestId)
    && isUuid(proof?.installationId)
    && BASE64URL_256.test(proof?.pollToken ?? '')
    && BASE64URL_256.test(proof?.pollChallenge ?? '')
    && BASE64URL_256.test(proof?.codeVerifier ?? '')
    && BASE64URL_256.test(proof?.codeChallenge ?? '')
    && BASE64URL_256.test(proof?.state ?? '')
    && proof.pollChallenge === sha256Base64Url(proof.pollToken)
    && proof.codeChallenge === sha256Base64Url(proof.codeVerifier);
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
  return message
    .replace(/#approval=[A-Za-z0-9_%~-]+/gu, '#approval=[redacted]')
    .replace(/("?(?:pollToken|codeVerifier|state|csrfToken|refreshToken|accessToken)"?\s*[:=]\s*)[^\s,}]+/giu, '$1[redacted]');
}

function sha256Base64Url(value) {
  return createHash('sha256').update(value, 'utf8').digest('base64url');
}

function trimTerminalPunctuation(candidate) {
  return candidate.replace(/[),.;]+$/u, '');
}
