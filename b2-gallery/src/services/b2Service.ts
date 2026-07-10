import axios from 'axios';
import { B2File, B2Connection, UploadProgress } from '../types';

const B2_API_URL = 'https://api001.backblazeb2.com/b2api/v2';

export const b2Service = {
  async authorize(
    appKeyId: string,
    appKey: string,
    bucketName: string
  ): Promise<B2Connection> {
    try {
      const authResponse = await axios.post(
        `${B2_API_URL}/b2_authorize_account`,
        {},
        {
          auth: {
            username: appKeyId,
            password: appKey
          }
        }
      );

      const { accountId, authorizationToken, apiUrl, downloadUrl } = authResponse.data;

      const bucketsResponse = await axios.post(
        `${apiUrl}/b2api/v2/b2_list_buckets`,
        { accountId },
        {
          headers: {
            Authorization: authorizationToken
          }
        }
      );

      const bucket = bucketsResponse.data.buckets.find(
        (b: any) => b.bucketName === bucketName
      );

      if (!bucket) {
        throw new Error(`Bucket "${bucketName}" not found`);
      }

      return {
        accountId,
        authToken: authorizationToken,
        apiUrl,
        bucketName,
        bucketId: bucket.bucketId,
        downloadUrl
      };
    } catch (error: any) {
      throw new Error(
        error.response?.data?.message || error.message || 'Authorization failed'
      );
    }
  },

  async listFiles(connection: B2Connection): Promise<B2File[]> {
    try {
      const response = await axios.post(
        `${connection.apiUrl}/b2api/v2/b2_list_file_versions`,
        {
          bucketId: connection.bucketId,
          maxFileCount: 1000
        },
        {
          headers: {
            Authorization: connection.authToken
          }
        }
      );

      return response.data.files || [];
    } catch (error: any) {
      throw new Error(
        error.response?.data?.message || error.message || 'Failed to list files'
      );
    }
  },

  async deleteFile(
    connection: B2Connection,
    fileId: string,
    fileName: string
  ): Promise<void> {
    try {
      await axios.post(
        `${connection.apiUrl}/b2api/v2/b2_delete_file_version`,
        {
          fileId,
          fileName
        },
        {
          headers: {
            Authorization: connection.authToken
          }
        }
      );
    } catch (error: any) {
      throw new Error(
        error.response?.data?.message || error.message || 'Failed to delete file'
      );
    }
  },

  async getUploadUrl(connection: B2Connection): Promise<{ uploadUrl: string; authToken: string }> {
    try {
      const response = await axios.post(
        `${connection.apiUrl}/b2api/v2/b2_get_upload_url`,
        {
          bucketId: connection.bucketId
        },
        {
          headers: {
            Authorization: connection.authToken
          }
        }
      );

      return {
        uploadUrl: response.data.uploadUrl,
        authToken: response.data.authorizationToken
      };
    } catch (error: any) {
      throw new Error(
        error.response?.data?.message || error.message || 'Failed to get upload URL'
      );
    }
  },

  async uploadFile(
    uploadUrl: string,
    authToken: string,
    file: File,
    onProgress?: (progress: UploadProgress) => void
  ): Promise<void> {
    try {
      const xhr = new XMLHttpRequest();

      return new Promise((resolve, reject) => {
        xhr.upload.addEventListener('progress', (event) => {
          if (event.lengthComputable && onProgress) {
            onProgress({
              loaded: event.loaded,
              total: event.total,
              percentage: Math.round((event.loaded / event.total) * 100)
            });
          }
        });

        xhr.addEventListener('load', () => {
          if (xhr.status === 200) {
            resolve();
          } else {
            reject(new Error('Upload failed'));
          }
        });

        xhr.addEventListener('error', () => {
          reject(new Error('Upload error'));
        });

        xhr.addEventListener('abort', () => {
          reject(new Error('Upload cancelled'));
        });

        xhr.open('POST', uploadUrl);
        xhr.setRequestHeader('Authorization', authToken);
        xhr.setRequestHeader('X-Bz-File-Name', file.name);
        xhr.setRequestHeader('Content-Type', 'application/octet-stream');

        xhr.send(file);
      });
    } catch (error: any) {
      throw new Error(error.message || 'Upload failed');
    }
  },

  async copyFile(
    connection: B2Connection,
    sourceFileId: string,
    newFileName: string
  ): Promise<void> {
    try {
      await axios.post(
        `${connection.apiUrl}/b2api/v2/b2_copy_file`,
        {
          sourceFileId,
          fileName: newFileName
        },
        {
          headers: {
            Authorization: connection.authToken
          }
        }
      );
    } catch (error: any) {
      throw new Error(
        error.response?.data?.message || error.message || 'Failed to copy file'
      );
    }
  }
};
