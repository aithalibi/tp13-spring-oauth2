/*
 * Fournisseur OpenID Connect minimal — utilise UNIQUEMENT pour la verification
 * locale du TP13 quand on ne dispose ni d'identifiants Google reels, ni d'un
 * serveur Keycloak (Docker).
 *
 * Il implements les 4 points requis par Spring Security pour le flux
 * authorization_code :
 *   1. /.well-known/openid-configuration   (decouverte / issuer-uri)
 *   2. /jwks                               (cle publique RSA de signature)
 *   3. /authorize  -> redirige avec un code
 *   4. /token      -> renvoie access_token + id_token signe RS256
 *   5. /userinfo   -> attributs du profil
 *
 * Lancement : node tools/mock-idp/server.js
 * Port      : 9090  (Keycloak du TP utilise 8180, Google 443)
 */
const http = require('http');
const crypto = require('crypto');
const url = require('url');

const PORT = process.env.PORT || 9090;
const ISSUER = `http://localhost:${PORT}`;
const CLIENT_ID = 'mock-oauth-client';

const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = publicKey.export({ format: 'jwk' });
jwk.kid = 'mock-key-1';
jwk.use = 'sig';
jwk.alg = 'RS256';

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');

function signIdToken(claims) {
  const header = { alg: 'RS256', typ: 'JWT', kid: jwk.kid };
  const payload = b64(header) + '.' + b64(claims);
  const sig = crypto.sign('RSA-SHA256', Buffer.from(payload), privateKey).toString('base64url');
  return payload + '.' + sig;
}

const codes = new Map();
const tokens = new Map();

const users = {
  yasmine: {
    sub: 'mock|yasmine',
    name: 'Yasmine Ait Halibi',
    given_name: 'Yasmine',
    family_name: 'Ait Halibi',
    email: 'yasmine.ait@ens.ma',
    email_verified: true,
    picture: 'https://ui-avatars.com/api/?name=Yasmine+Ait+Halibi&background=2b5797&color=fff&size=160',
    locale: 'fr'
  },
  etudiant: {
    sub: 'mock|etudiant',
    name: 'Etudiant ENS',
    given_name: 'Etudiant',
    family_name: 'ENS',
    email: 'etudiant@ens.ma',
    email_verified: true,
    picture: 'https://ui-avatars.com/api/?name=Etudiant+ENS&background=1e7e34&color=fff&size=160',
    locale: 'fr'
  }
};

const server = http.createServer((req, res) => {
  const parsed = url.parse(req.url, true);
  const path = parsed.pathname;
  const q = parsed.query;

  const json = (code, body) => {
    res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify(body));
  };

  if (path === '/.well-known/openid-configuration') {
    return json(200, {
      issuer: ISSUER,
      authorization_endpoint: `${ISSUER}/authorize`,
      token_endpoint: `${ISSUER}/token`,
      userinfo_endpoint: `${ISSUER}/userinfo`,
      jwks_uri: `${ISSUER}/jwks`,
      response_types_supported: ['code'],
      subject_types_supported: ['public'],
      id_token_signing_alg_values_supported: ['RS256'],
      scopes_supported: ['openid', 'profile', 'email'],
      token_endpoint_auth_methods_supported: ['client_secret_basic', 'client_secret_post'],
      claims_supported: ['sub', 'name', 'given_name', 'family_name', 'email', 'email_verified', 'picture', 'locale']
    });
  }

  if (path === '/jwks') {
    return json(200, { keys: [jwk] });
  }

  if (path === '/authorize') {
    // Page de choix de compte : simule l'ecran de connexion du fournisseur.
    if (!q.login) {
      const comptes = Object.keys(users).map((login) => {
        const suite = new URLSearchParams({ ...q, login });
        return `<li><a class="compte" href="/authorize?${suite}">
                  <img src="${users[login].picture}" alt=""><span><strong>${users[login].name}</strong>
                  <small>${users[login].email}</small></span></a></li>`;
      }).join('');
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(`<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8">
        <title>Mock IdP — choisir un compte</title>
        <style>
          body{font-family:system-ui,Segoe UI,sans-serif;background:#eef1f6;margin:0;display:flex;
               min-height:100vh;align-items:center;justify-content:center}
          .boite{background:#fff;border-radius:12px;padding:26px 30px;width:400px;
                 box-shadow:0 6px 24px rgba(20,30,60,.16)}
          h1{font-size:17px;margin:0 0 4px;color:#2b5797}
          p.sous{font-size:12px;color:#5a6478;margin:0 0 18px}
          ul{list-style:none;padding:0;margin:0;display:grid;gap:8px}
          a.compte{display:flex;gap:12px;align-items:center;padding:10px;border:1px solid #dbe2ec;
                   border-radius:9px;text-decoration:none;color:#1f2430;font-size:13px}
          a.compte:hover{background:#f4f7fb;border-color:#2b5797}
          img{width:38px;height:38px;border-radius:50%}
          span{display:flex;flex-direction:column}
          small{color:#5a6478;font-size:11px}
        </style></head><body><div class="boite">
        <h1>Mock Identity Provider</h1>
        <p class="sous">Choisissez le compte a utiliser pour cette application.</p>
        <ul>${comptes}</ul></div></body></html>`);
    }

    const user = users[q.login];
    if (!user) return json(400, { error: 'invalid_request', error_description: 'compte inconnu' });

    const code = crypto.randomBytes(16).toString('hex');
    codes.set(code, { user, nonce: q.nonce, clientId: q.client_id });

    const redirect = new URL(q.redirect_uri);
    redirect.searchParams.set('code', code);
    if (q.state) redirect.searchParams.set('state', q.state);
    res.writeHead(302, { Location: redirect.toString() });
    return res.end();
  }

  if (path === '/token' && req.method === 'POST') {
    let body = '';
    req.on('data', (c) => { body += c; });
    return req.on('end', () => {
      const p = new URLSearchParams(body);
      const entry = codes.get(p.get('code'));
      if (!entry) return json(400, { error: 'invalid_grant', error_description: 'code inconnu ou deja utilise' });
      codes.delete(p.get('code'));

      const now = Math.floor(Date.now() / 1000);
      const claims = {
        iss: ISSUER,
        azp: CLIENT_ID,
        aud: CLIENT_ID,
        sub: entry.user.sub,
        iat: now,
        exp: now + 3600,
        name: entry.user.name,
        given_name: entry.user.given_name,
        family_name: entry.user.family_name,
        email: entry.user.email,
        email_verified: entry.user.email_verified,
        picture: entry.user.picture,
        locale: entry.user.locale
      };
      if (entry.nonce) claims.nonce = entry.nonce;

      const accessToken = crypto.randomBytes(24).toString('hex');
      tokens.set(accessToken, entry.user);

      return json(200, {
        access_token: accessToken,
        token_type: 'Bearer',
        expires_in: 3600,
        scope: 'openid profile email',
        id_token: signIdToken(claims)
      });
    });
  }

  if (path === '/userinfo') {
    const auth = req.headers.authorization || '';
    const token = auth.replace(/^Bearer\s+/i, '');
    const user = tokens.get(token);
    if (!user) return json(401, { error: 'invalid_token' });
    const { sub, name, given_name, family_name, email, email_verified, picture, locale } = user;
    return json(200, { sub, name, given_name, family_name, email, email_verified, picture, locale });
  }

  json(404, { error: 'not_found', path });
});

server.listen(PORT, () => {
  console.log(`Mock OpenID Provider demarre sur ${ISSUER}`);
  console.log(`  issuer-uri : ${ISSUER}`);
  console.log(`  client-id  : ${CLIENT_ID}`);
});
