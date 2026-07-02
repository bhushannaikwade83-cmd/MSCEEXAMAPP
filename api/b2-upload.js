/**
 * B2 Upload API - Handles B2 authorization and file uploads server-side
 * Deploy to Vercel, not local
 */

import { createHash } from 'node:crypto';

export const config = {
  api: { bodyParser: false },
};

let b2AuthCache = null;

function env(...keys) {
  for (const k of keys) {
    const v = String(process.env[k] || '').trim();
    if (v) return v;
  }
  return '';
}

function requireB2Config() {
  const keyId = env('B2_KEY_ID');
  const applicationKey = env('B2_MASTER_KEY');
  const bucketName = env('B2_BUCKET_NAME');
  const bucketId = env('B2_BUCKET_ID');

  if (!keyId || !applicationKey || !bucketName || !bucketId) {
    throw new Error(
      'Missing B2 config. Set B2_KEY_ID, B2_MASTER_KEY, B2_BUCKET_NAME, and B2_BUCKET_ID in Vercel environment.'
    );
  }
  return { keyId, applicationKey, bucketName, bucketId };
}

async function b2AuthorizeAccount() {
  const now = Date.now();
  if (b2AuthCache && b2AuthCache.expiresAt > now) return b2AuthCache;

  const { keyId, applicationKey } = requireB2Config();
  const basic = Buffer.from(`${keyId}:${applicationKey}`).toString('base64');

  const r = await fetch('https://api.backblazeb2.com/b2api/v2/b2_authorize_account', {
    method: 'GET',
    headers: { Authorization: `Basic ${basic}` },
  });

  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(data.message || `b2_authorize_account failed (${r.status})`);

  b2AuthCache = {
    apiUrl: data.apiUrl,
    downloadUrl: data.downloadUrl,
    authorizationToken: data.authorizationToken,
    expiresAt: now + 23 * 60 * 60 * 1000,
  };

  return b2AuthCache;
}

async function b2ApiPost(apiUrl, path, authorizationToken, body) {
  const r = await fetch(`${apiUrl}/b2api/v2/${path}`, {
    method: 'POST',
    headers: {
      Authorization: authorizationToken,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body || {}),
  });

  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(data.message || `${path} failed (${r.status})`);
  return data;
}

async function readRawBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks);
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, HEAD');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-File-Name, Authorization');
  res.setHeader('Content-Type', 'application/json');

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  try {
    // Handle GET/HEAD - download/fetch photos from B2
    if (req.method === 'GET' || req.method === 'HEAD') {
      try {
        const keyParam = req.query.key;
        if (!keyParam) {
          return res.status(400).json({ error: 'Missing key parameter' });
        }

        const key = decodeURIComponent(String(keyParam));
        console.log(`📥 Proxying download: ${key}`);

        const { bucketName, bucketId } = requireB2Config();
        const auth = await b2AuthorizeAccount();

        // Get download authorization
        const authToken = await b2ApiPost(auth.apiUrl, 'b2_get_download_authorization', auth.authorizationToken, {
          bucketId,
          fileNamePrefix: key,
          validDurationInSeconds: 3600,
        });

        // Proxy the download
        const encodedKey = key.split('/').map(encodeURIComponent).join('/');
        const downloadUrl = `${auth.downloadUrl}/file/${encodeURIComponent(bucketName)}/${encodedKey}`;

        const response = await fetch(downloadUrl, {
          method: req.method,
          headers: {
            Authorization: authToken.authorizationToken,
          },
        });

        if (!response.ok) {
          console.error(`❌ B2 download failed: ${response.status}`);
          return res.status(response.status).send('Download failed');
        }

        // Copy headers
        const contentType = response.headers.get('content-type');
        if (contentType) res.setHeader('Content-Type', contentType);
        const contentLength = response.headers.get('content-length');
        if (contentLength) res.setHeader('Content-Length', contentLength);

        if (req.method === 'HEAD') {
          res.status(200).end();
          return;
        }

        // Stream the file
        const buffer = await response.arrayBuffer();
        return res.status(200).send(Buffer.from(buffer));
      } catch (error) {
        console.error('❌ Download error:', error.message);
        return res.status(500).json({ error: error.message || 'Download failed' });
      }
    }

    // Handle POST - upload photos to B2
    if (req.method === 'POST') {
      const fileName = req.headers['x-file-name'];
      const contentType = req.headers['content-type'] || 'application/octet-stream';

      if (!fileName) {
        return res.status(400).json({ error: 'Missing X-File-Name header' });
      }

      console.log(`📤 Uploading: ${fileName}`);

      const body = await readRawBody(req);

      if (!body || body.length === 0) {
        return res.status(400).json({ error: 'Empty file' });
      }

      const { bucketName, bucketId } = requireB2Config();

      console.log('🔐 Authorizing with B2...');
      const auth = await b2AuthorizeAccount();

      console.log('📍 Getting upload URL...');
      const uploadInfo = await b2ApiPost(auth.apiUrl, 'b2_get_upload_url', auth.authorizationToken, {
        bucketId,
      });

      const sha1 = createHash('sha1').update(body).digest('hex');

      console.log('⬆️ Uploading to B2...');
      const sanitizedFileName = fileName.replace(/\s+/g, '_');
      const uploadRes = await fetch(uploadInfo.uploadUrl, {
        method: 'POST',
        headers: {
          Authorization: uploadInfo.authorizationToken,
          'X-Bz-File-Name': sanitizedFileName,
          'Content-Type': contentType,
          'X-Bz-Content-Sha1': sha1,
        },
        body,
      });

      const uploadData = await uploadRes.json().catch(() => ({}));

      if (!uploadRes.ok) {
        console.error('❌ B2 Upload failed:', uploadData);
        return res.status(uploadRes.status).json({
          error: uploadData.message || `Upload failed (${uploadRes.status})`,
        });
      }

      const proxyUrl = `/api/b2-upload?key=${encodeURIComponent(sanitizedFileName)}`;

      console.log('✅ Upload successful, proxy URL:', proxyUrl);

      return res.status(200).json({
        success: true,
        url: proxyUrl,
        fileName: uploadData.fileName,
        fileId: uploadData.fileId,
      });
    }

    return res.status(405).json({ error: 'Method not allowed' });
  } catch (error) {
    console.error('❌ Error:', error.message);
    return res.status(500).json({
      success: false,
      error: error.message || 'Upload failed',
    });
  }
}
