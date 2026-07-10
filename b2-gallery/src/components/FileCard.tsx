import React from 'react';
import { motion } from 'framer-motion';
import { Copy, Download, Trash2, Edit2, Image } from 'lucide-react';
import { B2File } from '../types';
import { formatBytes, formatDate, getFileIcon, isImageFile } from '../utils/helpers';
import '../styles/FileCard.css';

interface FileCardProps {
  file: B2File;
  onCopy: (fileName: string) => void;
  onDownload: (fileName: string) => void;
  onDelete: (file: B2File) => void;
  onRename: (file: B2File) => void;
  downloadUrl: string;
  index: number;
}

export const FileCard: React.FC<FileCardProps> = ({
  file,
  onCopy,
  onDownload,
  onDelete,
  onRename,
  downloadUrl,
  index
}) => {
  const isImage = isImageFile(file.fileName);
  const fileIcon = getFileIcon(file.fileName);

  return (
    <motion.div
      className="file-card"
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{
        type: 'spring',
        damping: 25,
        stiffness: 300,
        delay: index * 0.05
      }}
      whileHover={{ y: -8, boxShadow: 'var(--shadow-lg)' }}
      layout
    >
      <motion.div
        className="file-preview"
        whileHover={{ scale: 1.05 }}
        transition={{ type: 'spring', damping: 25, stiffness: 300 }}
      >
        {isImage ? (
          <>
            <img
              src={`${downloadUrl}/file/${encodeURIComponent(file.fileName)}`}
              alt={file.fileName}
              className="file-image"
              onError={(e) => {
                (e.target as HTMLImageElement).style.display = 'none';
                const placeholder = (e.target as HTMLImageElement).nextElementSibling as HTMLElement;
                if (placeholder) placeholder.style.display = 'flex';
              }}
            />
            <div className="file-placeholder" style={{ display: 'none' }}>
              <Image size={48} />
            </div>
          </>
        ) : (
          <div className="file-icon-container">
            <span className="file-icon">{fileIcon}</span>
          </div>
        )}
      </motion.div>

      <div className="file-info">
        <h3 className="file-name" title={file.fileName}>
          {file.fileName}
        </h3>
        <div className="file-details">
          <span className="file-size">{formatBytes(file.size)}</span>
          <span className="file-date">{formatDate(file.uploadTimestamp)}</span>
        </div>
      </div>

      <div className="file-actions">
        <motion.button
          className="action-btn copy-btn"
          onClick={() => onCopy(file.fileName)}
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          title="Copy filename"
        >
          <Copy size={16} />
        </motion.button>
        <motion.button
          className="action-btn download-btn"
          onClick={() => onDownload(file.fileName)}
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          title="Download file"
        >
          <Download size={16} />
        </motion.button>
        <motion.button
          className="action-btn rename-btn"
          onClick={() => onRename(file)}
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          title="Rename file"
        >
          <Edit2 size={16} />
        </motion.button>
        <motion.button
          className="action-btn delete-btn"
          onClick={() => onDelete(file)}
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          title="Delete file"
        >
          <Trash2 size={16} />
        </motion.button>
      </div>
    </motion.div>
  );
};
