import express from 'express';
import cors from 'cors';
import axios from 'axios';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3001;

app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.raw({ type: 'application/octet-stream', limit: '50mb' }));

const B2_API_URL = 'https://api001.backblazeb2.com/b2api/v2';

// Cache for B2 auth token
let b2AuthCache = null;

// Helper to get B2 auth
async function getB2Auth() {
  const now = Date.now();
  if (b2AuthCache && b2AuthCache.expiresAt > now) {
    return b2AuthCache;
  }

  const keyId = process.env.VITE_B2_APP_KEY_ID;
  const appKey = process.env.VITE_B2_APP_KEY;

  if (!keyId || !appKey) {
    throw new Error('Missing B2 credentials in .env');
  }

  try {
    const response = await axios.post(
      `${B2_API_URL}/b2_authorize_account`,
      {},
      {
        auth: {
          username: keyId,
          password: appKey
        }
      }
    );

    b2AuthCache = {
      accountId: response.data.accountId,
      authToken: response.data.authorizationToken,
      apiUrl: response.data.apiUrl,
      downloadUrl: response.data.downloadUrl,
      expiresAt: now + 23 * 60 * 60 * 1000
    };

    return b2AuthCache;
  } catch (error) {
    throw new Error(`B2 auth failed: ${error.message}`);
  }
}

// Authorize endpoint
app.post('/api/b2/authorize', async (req, res) => {
  try {
    const auth = await getB2Auth();

    // Get buckets
    const bucketsResponse = await axios.post(
      `${auth.apiUrl}/b2api/v2/b2_list_buckets`,
      { accountId: auth.accountId },
      {
        headers: { Authorization: auth.authToken }
      }
    );

    const bucketName = process.env.VITE_B2_BUCKET_NAME;
    const bucket = bucketsResponse.data.buckets.find(b => b.bucketName === bucketName);

    if (!bucket) {
      return res.status(404).json({ error: `Bucket "${bucketName}" not found` });
    }

    res.json({
      accountId: auth.accountId,
      authToken: auth.authToken,
      apiUrl: auth.apiUrl,
      bucketName: bucket.bucketName,
      bucketId: bucket.bucketId,
      downloadUrl: auth.downloadUrl
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// List files endpoint
app.post('/api/b2/list-files', async (req, res) => {
  try {
    const auth = await getB2Auth();
    const { bucketId } = req.body;

    const response = await axios.post(
      `${auth.apiUrl}/b2api/v2/b2_list_file_versions`,
      { bucketId, maxFileCount: 1000 },
      { headers: { Authorization: auth.authToken } }
    );

    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get upload URL endpoint
app.post('/api/b2/get-upload-url', async (req, res) => {
  try {
    const auth = await getB2Auth();
    const { bucketId } = req.body;

    const response = await axios.post(
      `${auth.apiUrl}/b2api/v2/b2_get_upload_url`,
      { bucketId },
      { headers: { Authorization: auth.authToken } }
    );

    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Upload file endpoint
app.post('/api/b2/upload', async (req, res) => {
  try {
    const auth = await getB2Auth();
    const fileName = req.headers['x-file-name'];
    const contentType = req.headers['content-type'] || 'application/octet-stream';

    if (!fileName) {
      return res.status(400).json({ error: 'Missing X-File-Name header' });
    }

    // Get upload URL
    const uploadUrlResponse = await axios.post(
      `${auth.apiUrl}/b2api/v2/b2_get_upload_url`,
      { bucketId: process.env.VITE_B2_BUCKET_ID },
      { headers: { Authorization: auth.authToken } }
    );

    // Upload file
    const uploadResponse = await axios.post(
      uploadUrlResponse.data.uploadUrl,
      req.body,
      {
        headers: {
          Authorization: uploadUrlResponse.data.authorizationToken,
          'X-Bz-File-Name': fileName,
          'Content-Type': contentType,
          'X-Bz-Content-Sha1': 'unverified:' + require('crypto').createHash('sha1').update(req.body).digest('hex')
        }
      }
    );

    res.json(uploadResponse.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Delete file endpoint
app.post('/api/b2/delete-file', async (req, res) => {
  try {
    const auth = await getB2Auth();
    const { fileId, fileName } = req.body;

    const response = await axios.post(
      `${auth.apiUrl}/b2api/v2/b2_delete_file_version`,
      { fileId, fileName },
      { headers: { Authorization: auth.authToken } }
    );

    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Copy file endpoint (for rename)
app.post('/api/b2/copy-file', async (req, res) => {
  try {
    const auth = await getB2Auth();
    const { sourceFileId, fileName } = req.body;

    const response = await axios.post(
      `${auth.apiUrl}/b2api/v2/b2_copy_file`,
      { sourceFileId, fileName },
      { headers: { Authorization: auth.authToken } }
    );

    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, () => {
  console.log(`✅ B2 Proxy Server running on http://localhost:${PORT}`);
});
