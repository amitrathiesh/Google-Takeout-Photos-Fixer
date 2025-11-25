# Google Photos Takeout Fixer v1.0.1

## 🎯 **v1.0.1 - File Overwrite Support & External Drive Fixes!**

### 🚨 **Breaking Change Notice**
The app is now unsandboxed for full file system access. This fixes external drive permissions but changes security behavior.

## What's New in v1.0.1

### ✅ **Fixed Issues**
- **🔓 External Drive Access**: Resolved "Operation not permitted" errors when processing ZIP files on external drives
- **📂 Full Filesystem Access**: App now works with external drives (/Volumes/External/)
- **🛑 Removed Sandbox**: Disabled app sandboxing to enable necessary file operations
- **🔄 File Overwrite Support**: Automatically overwrite existing files when processing photos

### 🔧 **Technical Changes**
- Disabled `ENABLE_APP_SANDBOX` in Xcode build configuration
- App now behaves like traditional macOS applications with full filesystem permissions
- Added intelligent file overwrite functionality - existing files are replaced during processing
- Preserves all existing functionality while adding external drive support and file conflict resolution

## 🚀 Installation

**Recommended**: Download `takout-photos-fixer-v1.0.1-nosandbox.dmg`
1. Open the .dmg file
2. Drag to Applications folder
3. Right-click app → Select "Open" (security bypass required)
4. Works immediately on external drives!

## 📸 Usage With External Drives and File Overwrites

Now works seamlessly with:
- `/Volumes/External Drive/Google Takeout/takeout-*.zip` files
- Saving processed photos to external volumes
- **New**: Overwrite existing files automatically - no more "file exists" errors!
- Full read/write access to removable media

## 📋 File Overwrite Behavior

### What happens when a file already exists?
- **Before v1.0.1**: Processing would fail with "file exists" error
- **After v1.0.1**: 📝 **Files are automatically overwritten** with updated versions

This enables:
- **Reprocessing ZIPs** with updated metadata
- **Restoring backups** without file conflicts
- **Updating existing photos** with corrected EXIF data

## ⚠️ Security Notes

**Important Changes:**
- App is no longer sandboxed (has full filesystem access)
- May show additional security prompts on first launch
- Consider this when distributing to users with strict security requirements
- File overwrite cannot be undone - backups are recommended before processing

## 🏗️ Updated Technical Details

- **Security Model**: Unrestricted file access (formerly sandboxed)
- **File Access**: Complete filesystem permissions + file overwrite capability
- **External Drive Support**: ✅ Full support (/Volumes/*)
- **File Conflict Resolution**: ✅ Automatic overwrite enabled
- **Compatibility**: macOS 12.0+ (Universal Binary)
- **Build**: Development signed

## 📋 Migration from v1.0.0

Users upgrading from v1.0.0 will need to:
1. Download the new `takout-photos-fixer-v1.0.1-nosandbox.dmg`
2. Reinstall the app (replace old version)
3. Test external drive functionality
4. **⚠️  Note**: App now overwrites existing files automatically

## 🔒 Backward Compatibility

- All existing features preserved
- Same user interface and workflow
- Improved file access capabilities
- Enhanced file conflict handling
- No configuration changes required

## 🙌 Acknowledgments

Thank you for the feedback that led to these important fixes. External drive users can now process their Google Photos exports without permission errors, and the file overwrite feature eliminates common processing roadblocks!

---

*For v1.0.0 release notes, see the archived README.*
