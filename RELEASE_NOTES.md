# Google Photos Takeout Fixer v1.0.0

Welcome to the initial release of the Google Photos Takeout Fixer! This macOS application makes processing your Google Photos exports much easier.

## What's New

### ✨ Features
- **Automatic ZIP Processing**: Batch process multiple Google Takeout ZIP files
- **Metadata Embedding**: Automatically applies EXIF metadata from JSON files to your photos
- **Smart Merging**: Organizes and merges all extracted content into a single directory
- **Progress Tracking**: Live updates with statistics and activity logs
- **Reprocessing**: Catch missed metadata with one-click reprocessing
- **Native macOS UI**: Clean, professional interface that feels right at home

## 🚀 Installation

1. **Download**: Get the `takout-photos-fixer.dmg` file from below
2. **Install**: Open the .dmg and drag the app to your Applications folder
3. **First Launch**: Right-click the app → Open (required due to development signing)
4. **Go!**: Double-click to launch on subsequent uses

## 📸 Usage

1. Open the app
2. Click "Select ZIP Files" and choose your Google Takeout exports
3. Choose where to save processed photos
4. Hit "Start Processing" and watch the magic happen!

## 🔒 Security Note

This app uses development signing. Users will see a security warning the first time they open it. Right-click the app and select "Open" to bypass Gatekeeper.

## 🏗️ Technical Details

- Built with SwiftUI for modern macOS
- Sandboxed with appropriate file access entitlement
- Supports macOS 12.0+
- Universal binary (Intel + Apple Silicon)

## 🤝 Support

If you run into any issues:
- Check the app's log for detailed error messages
- Ensure you're running macOS 12.0 or later
- Verify your ZIP files are valid Google Takeout exports

## 🙏 Acknowledgments

Thanks to the macOS developer community for the inspiration and tools that made this possible!
