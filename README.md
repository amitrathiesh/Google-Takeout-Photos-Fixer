# Google Photos Takeout Fixer

A macOS application that processes and fixes Google Photos Takeout ZIP files by extracting, merging, and applying metadata from associated JSON files.

## 📋 Overview

Google Photos Takeout exports come as ZIP files containing images/videos alongside corresponding JSON metadata files. This app automatically:

- Extracts all ZIP files from a selected folder
- Merges the extracted content into a single output directory
- Applies EXIF metadata from JSON files to their corresponding media files
- Provides comprehensive progress tracking and statistics
- Offers reprocessing capabilities for missed metadata

## ✨ Features

### 🚀 Core Functionality
- **Batch ZIP Processing**: Select multiple Google Takeout ZIP files at once
- **Automatic Extraction**: Extracts and merges all ZIP content into organized output
- **Metadata Application**: Embeds JSON metadata into image/video EXIF data
- **Smart File Matching**: Automatically pairs media files with their metadata JSON files

### 📊 Progress Tracking
- **Live Processing Statistics**: Real-time counters during processing
- **Comprehensive Completion Summary**: Shows files processed, metadata applied, and missed files
- **Detailed Activity Log**: Timestamped log entries with auto-scrolling
- **Progress Indicators**: Visual progress bars for ZIP processing

### 🎨 User Experience
- **State-Driven UI**: Dynamic interface based on processing state
- **Mac-Native Design**: Seamlessly integrated titlebar and native macOS components
- **Dark/Light Mode**: Automatic theme adaptation
- **Professional Interface**: Clean, modern design with smooth animations

### 🔧 Advanced Features
- **Reprocessing Capability**: Re-check missed files for metadata
- **Error Handling**: Robust error recovery and user feedback
- **Background Processing**: Non-blocking file operations
- **Output Directory Selection**: Choose where processed files are saved

## 🛠️ Requirements

- **macOS 12.0+**
- **Swift 5.7+**
- **Xcode 14.0+** (for development)

## 🚀 Installation

### Option 1: Pre-built App
1. Download the latest .dmg file from the GitHub releases page
2. Open the .dmg file and drag the app to your Applications folder
3. **First launch**: Right-click the app in Applications → Open (due to unsigned app security)
4. Subsequent launches: Double-click as normal

### Option 2: Build from Source
```bash
# Clone the repository
git clone <repository-url>
cd takout-photos-fixer

# Open in Xcode
open takout-photos-fixer.xcodeproj

# Build and run (⌘R)
```

## 📖 Usage

### Getting Started
1. **Launch the App**: Open Google Photos Takeout Fixer from your Applications folder
2. **Select ZIP Files**: Click "Select ZIP Files" to choose your Google Takeout export files
3. **Choose Output Location**: Pick where you want processed photos saved (defaults to Downloads)
4. **Start Processing**: Click "Start Processing" to begin the operation

### Processing States

#### Welcome Screen
- Select Google Takeout ZIP files
- Choose output directory
- Ready to process state indication

#### Processing Screen
- Real-time progress tracking
- Live statistics header showing:
  - Current file being processed
  - Total files processed: `X`
  - Files with metadata applied: `Y`
  - Files missing metadata: `Z`
- Auto-scrolling activity log
- Stop processing option

#### Completion Screen
- Final comprehensive statistics:
  - Total files processed
  - Files with metadata successfully applied
  - Files missing metadata (with reprocessing option)
- Direct access to output folder
- Option to process new files

### Reprocessing Missed Files
If some files don't show metadata:
1. Review completion summary
2. Click "Recheck JSON for Missed Files"
3. App attempts secondary metadata matching
4. View updated statistics

## 🏗️ Architecture

### Core Components

#### `ContentView` (Main UI)
- State-driven user interface management
- File selection and output directory handling
- Progress tracking and statistics display
- Multi-state navigation (welcome → processing → completion)

#### `FileProcessor` (Core Processing Engine)
- ZIP file extraction and management
- Thread-safe synchronous processing
- Metadata application logic
- Progress and error callback handling

#### `ProcessorManager` (Processing Coordination)
- Asynchronous processing orchestration
- Cancellation and cleanup operations
- Task management across multiple ZIP files

#### `PhotoMetadata` (Data Models)
- JSON metadata parsing and processing
- EXIF data embedding utilities
- File matching algorithms

### Data Flow
```
ZIP Files → FileProcessor → Extraction → Metadata Matching → Output Directory
                    ↓
           Progress Callbacks → UI Updates → Live Statistics
                    ↓
           File Results → Completion State → Final Summary
```

## 🧩 Key Technologies

- **Swift 5.7+**: Primary programming language
- **SwiftUI**: Declarative user interface framework
- **Foundation**: File system operations and data handling
- **Combine**: Reactive state management
- **UniformTypeIdentifiers**: File type handling
- **System/Frameworks**: Native macOS APIs for ZIP processing

## 🔧 Development

### Project Structure
```
takout-photos-fixer/
├── ContentView.swift          # Main user interface
├── ContentViewModel.swift     # View model (alternative UI implementation)
├── FileProcessor.swift        # Core file processing logic
├── PhotoMetadata.swift        # Metadata handling and data models
├── PhotoMetadataProtocols.swift # Protocol definitions
├── takout_photos_fixerApp.swift # App entry point
└── Assets.xcassets/          # App icons and assets
```

### Building for Development
```bash
# Clean build
xcodebuild clean -project takout-photos-fixer.xcodeproj

# Debug build
xcodebuild -project takout-photos-fixer.xcodeproj -configuration Debug

# Release build
xcodebuild -project takout-photos-fixer.xcodeproj -configuration Release
```

### Testing
```bash
# Run unit tests
xcodebuild test -project takout-photos-fixer.xcodeproj
```

## 🤝 Contributing

### Development Setup
1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make changes and commit: `git commit -am 'Add feature'`
4. Push to fork: `git push origin feature-name`
5. Create a Pull Request

### Code Style
- Follow Swift API Design Guidelines
- Use descriptive variable names
- Add documentation for public APIs
- Handle errors appropriately
- Keep functions focused and single-purpose

### Adding Features
- Update documentation for new features
- Add unit tests for core functionality
- Maintain backward compatibility
- Test on multiple macOS versions when possible

## 📝 API Reference

### FileProcessor Methods

#### `processZipFilesSynchronously(zipURLs:outputDirectory:progressCallback:statusCallback:fileCallback:fileResultCallback:completion:)`
Main processing method that handles ZIP file extraction and metadata application.

**Parameters:**
- `zipURLs`: Array of ZIP file URLs to process
- `outputDirectory`: Directory where processed files will be saved
- `progressCallback`: Closure for progress updates
- `statusCallback`: Closure for status message updates
- `fileCallback`: Closure for current file processing updates
- `fileResultCallback`: Closure for individual file results
- `completion`: Closure called when processing completes

### PhotoMetadata Struct

Represents parsed Google Photos Takeout metadata with timestamp, description, location, and other EXIF data for embedding into media files.

## 🛡️ Error Handling

The application handles various error conditions:
- **ZIP Extraction Failures**: Logged with specific error messages
- **Metadata File Missing**: Marked as "missing metadata" for reprocessing
- **Permission Issues**: Clear user feedback for directory access problems
- **Corrupted Files**: Graceful degradation with partial processing

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙋 Support

### Troubleshooting

**App won't start:**
- Ensure you're running macOS 12.0 or later
- Verify the app is not damaged (right-click → Open)

**Processing fails:**
- Check that ZIP files are valid Google Takeout exports
- Ensure output directory has write permissions
- Verify sufficient disk space

**Metadata not applied:**
- Some photos may not have complete metadata in Google exports
- Try reprocessing to catch edge cases
- Check activity log for specific error messages

### Known Limitations

- Some very old Google Photos exports may have different JSON structure
- Large ZIP files (>50GB) may require significant processing time
- Network-attached storage may cause performance issues

## 🔄 Version History

### v1.0.0 (Current)
- Initial production release
- Complete Google Takeout ZIP processing
- Full metadata application
- Comprehensive UI with progress tracking
- Reprocessing capabilities for missed metadata

---

Made with ❤️ for the macOS community
