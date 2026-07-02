#!/bin/bash

echo "🔨 Building Flutter Web..."
flutter clean
flutter build web --release

if [ $? -eq 0 ]; then
  echo "✅ Build successful!"
  echo "📦 Web app is ready at: build/web/"
  echo ""
  echo "To deploy to Netlify:"
  echo "  cd build/web"
  echo "  zip -r ../web.zip ."
  echo "  # Then drag web.zip to Netlify"
  echo ""
  echo "Or use Netlify CLI:"
  echo "  netlify deploy --prod --dir=build/web"
else
  echo "❌ Build failed!"
  exit 1
fi
