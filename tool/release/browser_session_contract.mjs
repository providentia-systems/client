/** The homeowner namespace is selected for the complete browser lifecycle. */
export const HOMEOWNER_SESSION_COOKIES = Object.freeze([
  'providentia_homeowner_access',
  'providentia_homeowner_refresh',
  'providentia_homeowner_csrf',
]);

export function browserRequestHeaders({application = 'homeowner', body, headers = {}} = {}) {
  if (!['homeowner', 'admin'].includes(application)) {
    throw new Error('Browser acceptance requires an explicit supported application context.');
  }
  const result = {Accept: 'application/json', ...(body === undefined ? {} : {'Content-Type': 'application/json'})};
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() !== 'x-providentia-application') result[key] = value;
  }
  return {...result, 'X-Providentia-Application': application};
}
