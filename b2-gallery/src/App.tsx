import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { Upload, RefreshCw, Search, LogOut, Database } from 'lucide-react';
import { Toast } from './components/Toast';
import { FileCard } from './components/FileCard';
import { Modal } from './components/Modal';
import { LoadingSpinner } from './components/LoadingSpinner';
import { useToast } from './hooks/useToast';
import { b2Service } from './services/b2Service';
import { B2File, B2Connection } from './types';
import { searchFiles, sortFiles, calculateTotalSize, formatBytes } from './utils/helpers';
import './App.css';

function App() {
  const [appKeyId, setAppKeyId] = useState(import.meta.env.VITE_B2_APP_KEY_ID || '');
  const [appKey, setAppKey] = useState(import.meta.env.VITE_B2_APP_KEY || '');
  const [bucketName, setBucketName] = useState(import.meta.env.VITE_B2_BUCKET_NAME || '');
  const [isConnected, setIsConnected] = useState(false);
  const [connection, setConnection] = useState<B2Connection | null>(null);
  const [files, setFiles] = useState<B2File[]>([]);
  const [filteredFiles, setFilteredFiles] = useState<B2File[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<'name' | 'size' | 'date'>('date');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc');
  const [currentPage, setCurrentPage] = useState(1);
  const filesPerPage = 12;

  const [isUploadModalOpen, setIsUploadModalOpen] = useState(false);
  const [isRenameModalOpen, setIsRenameModalOpen] = useState(false);
  const [renameFile, setRenameFile] = useState<B2File | null>(null);
  const [newFileName, setNewFileName] = useState('');
  const [uploadFile, setUploadFile] = useState<File | null>(null);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [isUploading, setIsUploading] = useState(false);

  const { toasts, addToast, removeToast } = useToast();

  const handleConnect = async () => {
    if (!appKeyId.trim() || !appKey.trim() || !bucketName.trim()) {
      addToast('Please fill in all fields', 'error');
      return;
    }

    setIsLoading(true);
    try {
      const conn = await b2Service.authorize(appKeyId, appKey, bucketName);
      setConnection(conn);
      setIsConnected(true);
      addToast('Connected to B2 successfully!', 'success');
      await loadFiles(conn);
    } catch (error) {
      addToast(
        error instanceof Error ? error.message : 'Connection failed',
        'error'
      );
    } finally {
      setIsLoading(false);
    }
  };

  const loadFiles = async (conn: B2Connection) => {
    setIsLoading(true);
    try {
      const loadedFiles = await b2Service.listFiles(conn);
      setFiles(loadedFiles);
      setFilteredFiles(loadedFiles);
      setCurrentPage(1);
      addToast(`Loaded ${loadedFiles.length} files`, 'success');
    } catch (error) {
      addToast(
        error instanceof Error ? error.message : 'Failed to load files',
        'error'
      );
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    let results = searchFiles(files, searchQuery);
    results = sortFiles(results, sortBy, sortOrder);
    setFilteredFiles(results);
    setCurrentPage(1);
  }, [searchQuery, files, sortBy, sortOrder]);

  const handleUpload = async () => {
    if (!uploadFile || !connection) return;

    setIsUploading(true);
    try {
      const urlData = await b2Service.getUploadUrl(connection);
      await b2Service.uploadFile(
        urlData.uploadUrl,
        urlData.authToken,
        uploadFile,
        (progress) => {
          setUploadProgress(progress.percentage);
        }
      );
      addToast('File uploaded successfully!', 'success');
      setIsUploadModalOpen(false);
      setUploadFile(null);
      setUploadProgress(0);
      await loadFiles(connection);
    } catch (error) {
      addToast(
        error instanceof Error ? error.message : 'Upload failed',
        'error'
      );
    } finally {
      setIsUploading(false);
    }
  };

  const handleDelete = async (file: B2File) => {
    if (!connection) return;

    if (!window.confirm(`Delete "${file.fileName}"?`)) return;

    setIsLoading(true);
    try {
      await b2Service.deleteFile(connection, file.fileId, file.fileName);
      addToast('File deleted successfully', 'success');
      await loadFiles(connection);
    } catch (error) {
      addToast(
        error instanceof Error ? error.message : 'Delete failed',
        'error'
      );
    } finally {
      setIsLoading(false);
    }
  };

  const handleRename = (file: B2File) => {
    setRenameFile(file);
    setNewFileName(file.fileName);
    setIsRenameModalOpen(true);
  };

  const confirmRename = async () => {
    if (!renameFile || !connection || !newFileName.trim()) {
      addToast('Please enter a valid filename', 'error');
      return;
    }

    if (newFileName === renameFile.fileName) {
      addToast('New name must be different', 'error');
      return;
    }

    setIsLoading(true);
    try {
      await b2Service.copyFile(connection, renameFile.fileId, newFileName);
      await b2Service.deleteFile(connection, renameFile.fileId, renameFile.fileName);
      addToast('File renamed successfully', 'success');
      setIsRenameModalOpen(false);
      setRenameFile(null);
      await loadFiles(connection);
    } catch (error) {
      addToast(
        error instanceof Error ? error.message : 'Rename failed',
        'error'
      );
    } finally {
      setIsLoading(false);
    }
  };

  const handleCopy = (fileName: string) => {
    navigator.clipboard.writeText(fileName);
    addToast('Filename copied!', 'success');
  };

  const handleDownload = (fileName: string) => {
    if (!connection) return;
    const url = `${connection.downloadUrl}/file/${connection.bucketName}/${encodeURIComponent(
      fileName
    )}`;
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    addToast('Download started', 'success');
  };

  const totalPages = Math.ceil(filteredFiles.length / filesPerPage);
  const startIdx = (currentPage - 1) * filesPerPage;
  const pageFiles = filteredFiles.slice(startIdx, startIdx + filesPerPage);
  const totalSize = calculateTotalSize(files);

  return (
    <div className="app">
      <Toast toasts={toasts} onRemove={removeToast} />

      {!isConnected ? (
        <motion.div
          className="login-container"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.5 }}
        >
          <motion.div
            className="login-card"
            initial={{ scale: 0.95, y: 20 }}
            animate={{ scale: 1, y: 0 }}
            transition={{
              type: 'spring',
              damping: 25,
              stiffness: 300
            }}
          >
            <div className="login-header">
              <motion.div
                className="login-icon"
                animate={{ y: [0, -10, 0] }}
                transition={{
                  duration: 2,
                  repeat: Infinity
                }}
              >
                <Database size={48} />
              </motion.div>
              <h1>B2 Bucket Gallery</h1>
              <p>Professional File Manager for Backblaze B2</p>
            </div>

            <div className="login-form">
              <div className="form-group">
                <label htmlFor="appKeyId">App Key ID</label>
                <input
                  id="appKeyId"
                  type="text"
                  placeholder="Enter your B2 App Key ID"
                  value={appKeyId}
                  onChange={(e) => setAppKeyId(e.target.value)}
                  disabled={isLoading}
                />
              </div>

              <div className="form-group">
                <label htmlFor="appKey">App Key</label>
                <input
                  id="appKey"
                  type="password"
                  placeholder="Enter your B2 App Key"
                  value={appKey}
                  onChange={(e) => setAppKey(e.target.value)}
                  disabled={isLoading}
                />
              </div>

              <div className="form-group">
                <label htmlFor="bucketName">Bucket Name</label>
                <input
                  id="bucketName"
                  type="text"
                  placeholder="Enter your bucket name"
                  value={bucketName}
                  onChange={(e) => setBucketName(e.target.value)}
                  disabled={isLoading}
                />
              </div>

              <motion.button
                className="btn btn-primary btn-large"
                onClick={handleConnect}
                disabled={isLoading}
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.98 }}
              >
                {isLoading ? <LoadingSpinner size="sm" message="" /> : 'Connect to B2'}
              </motion.button>
            </div>

            <p className="login-help">
              Get your credentials from Backblaze B2 Console → App Keys
            </p>
          </motion.div>
        </motion.div>
      ) : (
        <>
          <header className="header">
            <motion.div
              className="header-content"
              initial={{ opacity: 0, y: -10 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.3 }}
            >
              <div className="header-left">
                <h1>📸 Gallery Manager</h1>
                <p>{connection?.bucketName}</p>
              </div>
              <motion.button
                className="btn btn-ghost"
                onClick={() => {
                  setIsConnected(false);
                  setConnection(null);
                  setFiles([]);
                }}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
              >
                <LogOut size={20} />
                Logout
              </motion.button>
            </motion.div>
          </header>

          <div className="controls">
            <motion.div
              className="search-bar"
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ duration: 0.3, delay: 0.1 }}
            >
              <Search size={20} />
              <input
                type="text"
                placeholder="Search files..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
            </motion.div>

            <div className="controls-right">
              <select
                value={`${sortBy}-${sortOrder}`}
                onChange={(e) => {
                  const [by, order] = e.target.value.split('-');
                  setSortBy(by as 'name' | 'size' | 'date');
                  setSortOrder(order as 'asc' | 'desc');
                }}
                className="select"
              >
                <option value="date-desc">Newest First</option>
                <option value="date-asc">Oldest First</option>
                <option value="name-asc">Name (A-Z)</option>
                <option value="name-desc">Name (Z-A)</option>
                <option value="size-asc">Size (Small to Large)</option>
                <option value="size-desc">Size (Large to Small)</option>
              </select>

              <motion.button
                className="btn btn-secondary"
                onClick={() => connection && loadFiles(connection)}
                disabled={isLoading}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
              >
                <RefreshCw size={20} />
                Refresh
              </motion.button>

              <motion.button
                className="btn btn-primary"
                onClick={() => setIsUploadModalOpen(true)}
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
              >
                <Upload size={20} />
                Upload
              </motion.button>
            </div>
          </div>

          <motion.div
            className="stats"
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.3, delay: 0.2 }}
          >
            <div className="stat">
              <span className="stat-value">{files.length}</span>
              <span className="stat-label">Total Files</span>
            </div>
            <div className="stat">
              <span className="stat-value">{formatBytes(totalSize)}</span>
              <span className="stat-label">Total Size</span>
            </div>
            <div className="stat">
              <span className="stat-value">{filteredFiles.length}</span>
              <span className="stat-label">Filtered</span>
            </div>
          </motion.div>

          <div className="gallery-container">
            {isLoading ? (
              <LoadingSpinner message="Loading files..." />
            ) : filteredFiles.length === 0 ? (
              <motion.div
                className="empty-state"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ duration: 0.3 }}
              >
                <span className="empty-icon">📁</span>
                <h2>No Files Found</h2>
                <p>Upload your first file or adjust your search</p>
              </motion.div>
            ) : (
              <>
                <motion.div
                  className="gallery"
                  initial="hidden"
                  animate="visible"
                  variants={{
                    hidden: { opacity: 0 },
                    visible: {
                      opacity: 1,
                      transition: {
                        staggerChildren: 0.05
                      }
                    }
                  }}
                >
                  {pageFiles.map((file, idx) => (
                    <FileCard
                      key={file.fileId}
                      file={file}
                      onCopy={handleCopy}
                      onDownload={handleDownload}
                      onDelete={handleDelete}
                      onRename={handleRename}
                      downloadUrl={connection?.downloadUrl || ''}
                      index={idx}
                    />
                  ))}
                </motion.div>

                {totalPages > 1 && (
                  <motion.div
                    className="pagination"
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    transition={{ duration: 0.3 }}
                  >
                    <button
                      onClick={() => setCurrentPage(1)}
                      disabled={currentPage === 1}
                      className="btn btn-secondary"
                    >
                      First
                    </button>
                    <button
                      onClick={() => setCurrentPage(p => Math.max(1, p - 1))}
                      disabled={currentPage === 1}
                      className="btn btn-secondary"
                    >
                      Previous
                    </button>
                    <div className="page-info">
                      Page {currentPage} of {totalPages}
                    </div>
                    <button
                      onClick={() => setCurrentPage(p => Math.min(totalPages, p + 1))}
                      disabled={currentPage === totalPages}
                      className="btn btn-secondary"
                    >
                      Next
                    </button>
                    <button
                      onClick={() => setCurrentPage(totalPages)}
                      disabled={currentPage === totalPages}
                      className="btn btn-secondary"
                    >
                      Last
                    </button>
                  </motion.div>
                )}
              </>
            )}
          </div>
        </>
      )}

      <Modal
        isOpen={isUploadModalOpen}
        title="Upload File"
        onClose={() => {
          setIsUploadModalOpen(false);
          setUploadFile(null);
          setUploadProgress(0);
        }}
        size="md"
      >
        <div className="modal-form">
          <input
            type="file"
            onChange={(e) => setUploadFile(e.target.files?.[0] || null)}
            disabled={isUploading}
            className="file-input"
          />
          {uploadFile && (
            <p className="file-info">
              Selected: {uploadFile.name} ({formatBytes(uploadFile.size)})
            </p>
          )}
          {isUploading && (
            <div className="upload-progress">
              <div className="progress-bar">
                <motion.div
                  className="progress-fill"
                  initial={{ width: 0 }}
                  animate={{ width: `${uploadProgress}%` }}
                  transition={{ type: 'tween', duration: 0.1 }}
                />
              </div>
              <p className="progress-text">{uploadProgress}%</p>
            </div>
          )}
          <div className="modal-actions">
            <motion.button
              className="btn btn-secondary"
              onClick={() => setIsUploadModalOpen(false)}
              disabled={isUploading}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
            >
              Cancel
            </motion.button>
            <motion.button
              className="btn btn-primary"
              onClick={handleUpload}
              disabled={!uploadFile || isUploading}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
            >
              {isUploading ? 'Uploading...' : 'Upload'}
            </motion.button>
          </div>
        </div>
      </Modal>

      <Modal
        isOpen={isRenameModalOpen}
        title="Rename File"
        onClose={() => {
          setIsRenameModalOpen(false);
          setRenameFile(null);
        }}
        size="md"
      >
        <div className="modal-form">
          <div className="form-group">
            <label>New Filename</label>
            <input
              type="text"
              value={newFileName}
              onChange={(e) => setNewFileName(e.target.value)}
              disabled={isLoading}
            />
          </div>
          <div className="modal-actions">
            <motion.button
              className="btn btn-secondary"
              onClick={() => setIsRenameModalOpen(false)}
              disabled={isLoading}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
            >
              Cancel
            </motion.button>
            <motion.button
              className="btn btn-primary"
              onClick={confirmRename}
              disabled={isLoading}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
            >
              {isLoading ? 'Renaming...' : 'Rename'}
            </motion.button>
          </div>
        </div>
      </Modal>
    </div>
  );
}

export default App;
