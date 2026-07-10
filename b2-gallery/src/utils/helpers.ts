import { B2File } from '../types';

export const formatBytes = (bytes: number): string => {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
};

export const formatDate = (timestamp: number): string => {
  return new Date(timestamp).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });
};

export const getFileExtension = (fileName: string): string => {
  return fileName.split('.').pop()?.toLowerCase() || '';
};

export const getFileIcon = (fileName: string): string => {
  const ext = getFileExtension(fileName);
  const iconMap: Record<string, string> = {
    jpg: '🖼️', jpeg: '🖼️', png: '🖼️', gif: '🖼️', webp: '🖼️', svg: '🖼️', bmp: '🖼️',
    pdf: '📄', doc: '📝', docx: '📝', txt: '📋', rtf: '📝',
    xls: '📊', xlsx: '📊', csv: '📊', numbers: '📊',
    ppt: '🎬', pptx: '🎬', key: '🎬',
    zip: '📦', rar: '📦', '7z': '📦', tar: '📦', gz: '📦',
    mp3: '🎵', mp4: '🎬', mov: '🎬', avi: '🎬', mkv: '🎬', wav: '🎵', flac: '🎵',
    js: '⚙️', ts: '⚙️', jsx: '⚙️', tsx: '⚙️', python: '🐍', py: '🐍', java: '☕',
    json: '⚙️', xml: '⚙️', html: '🌐', css: '🎨', php: '🌐', c: '⚙️', cpp: '⚙️',
    exe: '⚡', app: '⚡', dmg: '⚡', iso: '💿'
  };

  return iconMap[ext] || '📁';
};

export const searchFiles = (files: B2File[], query: string): B2File[] => {
  if (!query.trim()) return files;
  const lowerQuery = query.toLowerCase();
  return files.filter(file =>
    file.fileName.toLowerCase().includes(lowerQuery)
  );
};

export const sortFiles = (
  files: B2File[],
  sortBy: 'name' | 'size' | 'date',
  order: 'asc' | 'desc'
): B2File[] => {
  const sorted = [...files].sort((a, b) => {
    let comparison = 0;

    switch (sortBy) {
      case 'name':
        comparison = a.fileName.localeCompare(b.fileName);
        break;
      case 'size':
        comparison = a.size - b.size;
        break;
      case 'date':
        comparison = a.uploadTimestamp - b.uploadTimestamp;
        break;
    }

    return order === 'asc' ? comparison : -comparison;
  });

  return sorted;
};

export const generateId = (): string => {
  return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
};

export const escapeHtml = (text: string): string => {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
};

export const calculateTotalSize = (files: B2File[]): number => {
  return files.reduce((sum, file) => sum + (file.size || 0), 0);
};

export const isImageFile = (fileName: string): boolean => {
  const imageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp'];
  return imageExts.includes(getFileExtension(fileName));
};
