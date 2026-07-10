# 🚀 Quick Setup Guide

## Prerequisites
- Node.js 16+ installed
- npm or yarn
- B2 bucket set to **PUBLIC** ✅

## Installation

1. **Navigate to the project directory:**
```bash
cd /Users/bhushan/Desktop/PROJECTS/MSCEEXAMAPP/b2-gallery
```

2. **Install dependencies:**
```bash
npm install
```

3. **Configure credentials (.env file):**
The `.env` file is already pre-configured with:
- `VITE_B2_APP_KEY_ID=379cd0b52bbf`
- `VITE_B2_APP_KEY=004a72718b0ba180f5b742b7a1f4840d3c9ec904b4`
- `VITE_B2_BUCKET_NAME=attendance-students-photos`
- `VITE_B2_BUCKET_ID=2357799c9d705bc592cb0b1f`

**No changes needed!** Just use it as is.

## Run Development Server

```bash
npm run dev
```

This will:
- Start the development server
- Open automatically at `http://localhost:5173`
- Enable hot reload for code changes

## Build for Production

```bash
npm run build
```

Creates optimized production build in the `dist` folder.

## Features Available

✅ **Upload files** - Add files to your B2 bucket  
✅ **Download files** - Download directly to your computer  
✅ **Delete files** - Remove files with confirmation  
✅ **Rename files** - Copy and rename files  
✅ **Search files** - Real-time filename search  
✅ **Sort files** - By name, size, or date  
✅ **Pagination** - Navigate through files (12 per page)  
✅ **Image preview** - See thumbnails of image files  
✅ **File icons** - Visual indicators for file types  
✅ **Smooth animations** - Beautiful Framer Motion animations  
✅ **Toast notifications** - Feedback for all actions  
✅ **Responsive design** - Works on mobile & desktop  

## Troubleshooting

### Port 5173 already in use?
```bash
npm run dev -- --port 5174
```

### Dependencies not installing?
```bash
rm -rf node_modules package-lock.json
npm install
```

### CORS errors?
Make sure your B2 bucket is set to **PUBLIC**. If it's private, you'll need to set up a backend proxy.

## API Credentials Used

- **App Key ID:** 379cd0b52bbf
- **App Key:** 004a72718b0ba180f5b742b7a1f4840d3c9ec904b4 (from MSCEEXAMAPP/.env.production)
- **Bucket:** attendance-students-photos
- **Bucket ID:** 2357799c9d705bc592cb0b1f

✅ All from MSCEEXAMAPP project!

## File Structure

```
b2-gallery/
├── src/
│   ├── components/        # React components
│   ├── services/          # B2 API integration
│   ├── hooks/             # Custom hooks
│   ├── styles/            # Component styles
│   ├── utils/             # Helper functions
│   ├── types/             # TypeScript types
│   ├── App.tsx            # Main app
│   └── main.tsx           # Entry point
├── index.html             # HTML template
├── package.json           # Dependencies
├── .env                   # Environment variables
├── vite.config.ts         # Vite config
├── tsconfig.json          # TypeScript config
└── README.md              # Full documentation
```

---

**Ready to go!** 🎉

```bash
npm install && npm run dev
```
