# B2 Bucket Gallery - React Application

A professional, beautifully animated React website for managing Backblaze B2 buckets with full CRUD operations, search, pagination, and more.

## 🚀 Features

- **B2 Integration**: Direct connection to Backblaze B2 API
- **File Management**: Upload, download, delete, rename files
- **Search & Sort**: Real-time file search with multiple sort options
- **Pagination**: Navigate through files with smooth pagination
- **Animations**: Beautiful animations powered by Framer Motion
- **Responsive Design**: Mobile-friendly interface
- **Toast Notifications**: User feedback for all actions
- **Environment Variables**: Secure credential management with .env
- **TypeScript**: Type-safe code
- **Modern Stack**: React 18, Vite, Framer Motion, Lucide Icons

## 🔧 Setup Instructions

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment Variables

The `.env` file is pre-configured with B2 credentials from MSCEEXAMAPP:
- B2B_APP_KEY_ID=379cd0b52bbf
- B2B_APP_KEY=004a72718b0ba180f5b742b7a1f4840d3c9ec904b4
- B2B_BUCKET_NAME=attendance-students-photos
- B2B_BUCKET_ID=2357799c9d705bc592cb0b1f

### 3. Run Development Server

```bash
npm run dev
```

The app will open in your browser at `http://localhost:5173`

### 4. Build for Production

```bash
npm run build
```

## 📁 Project Structure

```
src/
├── components/          # React components
│   ├── FileCard.tsx    # Individual file card
│   ├── Modal.tsx       # Reusable modal
│   ├── Toast.tsx       # Toast notifications
│   └── LoadingSpinner.tsx
├── hooks/              # Custom React hooks
│   └── useToast.ts
├── services/           # API services
│   └── b2Service.ts    # B2 API integration
├── styles/             # CSS styles
├── types/              # TypeScript types
│   └── index.ts
├── utils/              # Helper functions
│   └── helpers.ts
├── App.tsx            # Main app component
├── main.tsx           # Entry point
└── index.css          # Global styles
```

## 🎨 Features Breakdown

### File Management
- **Upload**: Upload files with progress tracking
- **Download**: Direct download to your computer
- **Delete**: Remove files with confirmation
- **Rename**: Copy & rename files atomically
- **Copy**: Copy filenames to clipboard

### Search & Sort
- Real-time filename search
- Sort by name, size, or date
- Ascending/descending order
- Persistent sorting

### UI/UX
- Smooth animations on all interactions
- Loading states with spinners
- Toast notifications for feedback
- Responsive grid layout
- Mobile-optimized controls

## 🔐 Security Notes

- Credentials are stored in `.env` (never commit this file!)
- Add `.env` to `.gitignore`
- Use App Keys with minimal required permissions

## 📝 Technologies Used

- **React 18**: UI library
- **Vite**: Build tool
- **TypeScript**: Type safety
- **Framer Motion**: Animations
- **Lucide React**: Icons
- **Axios**: HTTP client

## 📞 Support

For B2 API issues: [Backblaze Support](https://www.backblaze.com/support.html)
For React issues: [React Docs](https://react.dev)

---

Built with ❤️ for MSCEEXAMAPP
