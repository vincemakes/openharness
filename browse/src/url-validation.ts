/**
 * URL validation for navigation commands — blocks dangerous schemes and cloud metadata endpoints.
 * Localhost and private IPs are allowed (primary use case: QA testing local dev servers).
 */

const BLOCKED_METADATA_HOSTS = new Set([
  '169.254.169.254',  // AWS/GCP/Azure instance metadata
  'fd00::',           // IPv6 unique local (metadata in some cloud setups)
  'metadata.google.internal', // GCP metadata
]);

/**
 * Normalize hostname for blocklist comparison.
 */
function normalizeHostname(hostname: string): string {
  let h = hostname.startsWith('[') && hostname.endsWith(']')
    ? hostname.slice(1, -1)
    : hostname;
  if (h.endsWith('.')) h = h.slice(0, -1);
  return h;
}

/**
 * Check if a hostname resolves to the link-local metadata IP 169.254.169.254.
 */
function isMetadataIp(hostname: string): boolean {
  try {
    const probe = new URL(`http://${hostname}`);
    const normalized = probe.hostname;
    if (BLOCKED_METADATA_HOSTS.has(normalized)) return true;
    if (normalized.endsWith('.') && BLOCKED_METADATA_HOSTS.has(normalized.slice(0, -1))) return true;
  } catch {
    // Not a valid hostname
  }
  return false;
}

export function validateNavigationUrl(url: string): void {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error(`Invalid URL: ${url}`);
  }

  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new Error(
      `Blocked: scheme "${parsed.protocol}" is not allowed. Only http: and https: URLs are permitted.`
    );
  }

  const hostname = normalizeHostname(parsed.hostname.toLowerCase());

  if (BLOCKED_METADATA_HOSTS.has(hostname) || isMetadataIp(hostname)) {
    throw new Error(
      `Blocked: ${parsed.hostname} is a cloud metadata endpoint. Access is denied for security.`
    );
  }
}
