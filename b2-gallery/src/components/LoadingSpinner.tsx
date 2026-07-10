import React from 'react';
import { motion } from 'framer-motion';
import '../styles/LoadingSpinner.css';

interface LoadingSpinnerProps {
  message?: string;
  size?: 'sm' | 'md' | 'lg';
}

export const LoadingSpinner: React.FC<LoadingSpinnerProps> = ({
  message = 'Loading...',
  size = 'md'
}) => {
  const sizeMap = { sm: 30, md: 50, lg: 70 };

  return (
    <div className={`loading-container loading-${size}`}>
      <motion.div
        className="spinner"
        animate={{ rotate: 360 }}
        transition={{
          duration: 2,
          repeat: Infinity,
          ease: 'linear'
        }}
        style={{
          width: sizeMap[size],
          height: sizeMap[size]
        }}
      >
        <svg viewBox="0 0 50 50" fill="none" xmlns="http://www.w3.org/2000/svg">
          <circle
            cx="25"
            cy="25"
            r="20"
            stroke="url(#gradient)"
            strokeWidth="2"
            strokeDasharray="31.4 125.6"
          />
          <defs>
            <linearGradient
              id="gradient"
              x1="0%"
              y1="0%"
              x2="100%"
              y2="100%"
            >
              <stop offset="0%" stopColor="var(--primary)" />
              <stop offset="100%" stopColor="var(--primary-dark)" />
            </linearGradient>
          </defs>
        </svg>
      </motion.div>
      {message && <p className="loading-message">{message}</p>}
    </div>
  );
};
