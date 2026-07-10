export interface B2File {
  fileId: string;
  fileName: string;
  size: number;
  uploadTimestamp: number;
  contentType: string;
  fileInfo: Record<string, string>;
  action: string;
}

export interface B2Connection {
  accountId: string;
  authToken: string;
  apiUrl: string;
  bucketName: string;
  bucketId: string;
  downloadUrl: string;
}

export interface UploadProgress {
  loaded: number;
  total: number;
  percentage: number;
}

export interface Toast {
  id: string;
  message: string;
  type: 'success' | 'error' | 'info' | 'warning';
  duration?: number;
}
