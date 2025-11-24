import Foundation
import ImageIO
import CoreGraphics
import AVFoundation
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

/// FileProcessor: Core Engine for Google Photos Takeout Processing
///
/// This class handles the complete pipeline for processing Google Photos Takeout ZIP files.
/// It extracts ZIP archives, locates media files, applies JSON metadata to EXIF data,
/// and manages the entire file processing workflow with comprehensive error handling
/// and progress reporting.
///
/// **Key Features:**
/// - Synchronous and asynchronous ZIP file processing
/// - Automatic metadata detection and application
/// - Support for multiple file formats (JPG, JPEG, HEIC, MP4, MOV)
/// - Robust error handling and recovery
/// - Progress callbacks for UI updates
/// - Edited file metadata inheritance from original files
///
/// **Processing Pipeline:**
/// 1. ZIP Extraction → 2. Media File Discovery → 3. Metadata Matching → 4. EXIF Application → 5. Output
///
/// - Note: Designed for background processing with no UI blocking operations
///
class FileProcessor {
    private let supportedImageExtensions = ["jpg", "jpeg", "heic"]
    private let supportedVideoExtensions = ["mp4", "mov"]

    // MARK: - Public Interface

    func processZipFiles(zipURLs: [URL], outputDirectory: URL, progressCallback: @escaping (UUID, Double, Int, Int) -> Void, statusCallback: ((String) -> Void)? = nil, fileCallback: ((String) -> Void)? = nil) async throws -> [(UUID, Result<String, Error>)] {
        var results: [(UUID, Result<String, Error>)] = []

        statusCallback?("Starting to process \(zipURLs.count) ZIP file(s)...")

        for (index, zipURL) in zipURLs.enumerated() {
            let uuid = UUID()
            statusCallback?("Processing ZIP \(index + 1)/\(zipURLs.count): \(zipURL.lastPathComponent)")

            do {
                let extractPath = try await extractZip(at: zipURL, statusCallback: statusCallback)
                let result = try await processExtractedFiles(at: extractPath, outputDirectory: outputDirectory, zipID: uuid, progressCallback: progressCallback, statusCallback: statusCallback, fileCallback: fileCallback)
                statusCallback?("Completed: \(zipURL.lastPathComponent)")
                results.append((uuid, .success(result)))
            } catch {
                statusCallback?("Error processing: \(zipURL.lastPathComponent) - \(error.localizedDescription)")
                results.append((uuid, .failure(error)))
            }
        }

        statusCallback?("Processing complete! Processed \(results.count) ZIP file(s)")
        return results
    }

    // Synchronous version for true background processing - no async/await anywhere
    func processZipFilesSynchronously(
        zipURLs: [URL],
        outputDirectory: URL,
        progressCallback: @escaping (UUID, Double, Int, Int) -> Void,
        statusCallback: ((String) -> Void)?,
        fileCallback: ((String) -> Void)?,
        fileResultCallback: ((ProcessingResult) -> Void)? = nil,
        completion: @escaping ([(UUID, Result<String, Error>)]?, Error?) -> Void
    ) {
        statusCallback?("Starting to process \(zipURLs.count) ZIP file(s)...")

        var finalResults: [(UUID, Result<String, Error>)] = []

        for (index, zipURL) in zipURLs.enumerated() {
            let uuid = UUID()
            statusCallback?("Processing ZIP \(index + 1)/\(zipURLs.count): \(zipURL.lastPathComponent)")

            do {
                // Synchronous ZIP extraction
                let extractPath = try self.extractZipSynchronously(at: zipURL, statusCallback: statusCallback)
                let result = try self.processExtractedFilesSynchronously(
                    at: extractPath,
                    outputDirectory: outputDirectory,
                    zipID: uuid,
                    progressCallback: progressCallback,
                    statusCallback: statusCallback,
                    fileCallback: fileCallback
                )
                statusCallback?("Completed: \(zipURL.lastPathComponent)")
                finalResults.append((uuid, .success(result)))
            } catch {
                statusCallback?("Error processing: \(zipURL.lastPathComponent) - \(error.localizedDescription)")
                finalResults.append((uuid, .failure(error)))
                completion(nil, error)
                return
            }
        }

        statusCallback?("Processing complete! Processed \(finalResults.count) ZIP file(s)")
        completion(finalResults, nil)
    }

    // Synchronous ZIP extraction
    private func extractZipSynchronously(at zipURL: URL, statusCallback: ((String) -> Void)? = nil) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let extractPath = tempDir.appendingPathComponent("extracted")

        // Create extraction directory
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: extractPath, withIntermediateDirectories: true)

        // Use Process synchronously - blocks until complete
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-x", "-k", "--sequesterRsrc", zipURL.path, extractPath.path]
        task.qualityOfService = .default

        // Setup pipes for output capture
        let pipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errorPipe

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus == 0 {
            return extractPath
        } else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown ditto error"
            try? fileManager.removeItem(at: tempDir)
            throw NSError(domain: "ZIPExtractionError", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "ditto extraction error: \(errorMessage)"])
        }
    }

    // Synchronous directory processing
    private func processExtractedFilesSynchronously(
        at directory: URL,
        outputDirectory: URL,
        zipID: UUID,
        progressCallback: @escaping (UUID, Double, Int, Int) -> Void,
        statusCallback: ((String) -> Void)?,
        fileCallback: ((String) -> Void)?,
        fileResultCallback: ((ProcessingResult) -> Void)? = nil
    ) throws -> String {
        var filesProcessed = 0
        let mediaFiles = findMediaFiles(in: directory)

        statusCallback?("Found \(mediaFiles.count) media files to process")
        progressCallback(zipID, 0.0, mediaFiles.count, 0)

        for mediaFile in mediaFiles {
            let filename = mediaFile.lastPathComponent
            fileCallback?(filename)

            // Process file and create result
            let result = try self.processMediaFileSynchronously(
                mediaFile: mediaFile,
                outputDirectory: outputDirectory,
                extractedDirectory: directory
            )

            // Report result through callback
            fileResultCallback?(result)

            filesProcessed += 1
            let progress = Double(filesProcessed) / Double(mediaFiles.count)
            progressCallback(zipID, progress, mediaFiles.count, filesProcessed)
        }

        statusCallback?("ZIP processing completed: \(filesProcessed)/\(mediaFiles.count) files processed")

        try? FileManager.default.removeItem(at: directory)

        return "Processed \(filesProcessed) / \(mediaFiles.count) files"
    }

    // Synchronous media file processing - returns ProcessingResult instead of throwing
    private func processMediaFileSynchronously(
        mediaFile: URL,
        outputDirectory: URL,
        extractedDirectory: URL
    ) throws -> ProcessingResult {
        let filename = mediaFile.lastPathComponent

        // Try to find metadata file with both possible suffixes
        let (jsonURL, metadataVariant) = try self.findMetadataFile(for: mediaFile)

        var cleanedRelativePath = filename

        if let takeoutIndex = mediaFile.path.components(separatedBy: "/").firstIndex(of: "Takeout") {
            let components = mediaFile.path.components(separatedBy: "/")
            let relativeComponents = components[takeoutIndex..<components.count]
            cleanedRelativePath = relativeComponents.joined(separator: "/")
        }

        let outputURL = outputDirectory.appendingPathComponent(cleanedRelativePath)
        let outputDir = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Set file attributes synchronously
        let currentDate = Date()
        try FileManager.default.setAttributes([
            FileAttributeKey.creationDate: currentDate,
            FileAttributeKey.modificationDate: currentDate
        ], ofItemAtPath: outputDir.path)

        let fileExtension = mediaFile.pathExtension.lowercased()
        var finalMetadata: PhotoMetadata?

        // Check for edited file pattern and find original metadata
        if filename.contains("-edited.") {
            // Try to find original file's metadata for edited version
            finalMetadata = try self.findOriginalMetadataForEditedFile(mediaFile: mediaFile, extractedDirectory: extractedDirectory)
        }

        // If we don't have metadata from inheritance, check normal metadata file
        if finalMetadata == nil && jsonURL != nil {
            do {
                let data = try Data(contentsOf: jsonURL!)
                let decoder = JSONDecoder()
                finalMetadata = try decoder.decode(PhotoMetadata.self, from: data)

                // Log which variant of metadata file was found
                if let variant = metadataVariant {
                    print("📋 Found metadata file variant: \(variant)")
                }
            } catch {
                // Failed to parse metadata, will fall back to copying file
            }
        }

        // Process file with metadata (inherited or original) and return result
        let metadataStatus: ProcessingResult.MetadataStatus
        let processedWithMetadata: Bool

        if let metadata = finalMetadata {
            metadataStatus = filename.contains("-edited.") ? .inheritedFromOriginal : .foundAndApplied
            processedWithMetadata = true

            if supportedImageExtensions.contains(fileExtension) {
                try self.processImageSynchronously(
                    mediaFile: mediaFile,
                    metadata: metadata,
                    outputURL: outputURL
                )
            } else if supportedVideoExtensions.contains(fileExtension) {
                let data = try Data(contentsOf: mediaFile)
                try data.write(to: outputURL)
            }

            try updateFileTimestamps(at: outputURL, date: metadata.takenDate)

            // Remove the metadata file we found and used
            if let jsonURLToRemove = jsonURL {
                try? FileManager.default.removeItem(at: jsonURLToRemove)
            }

        } else {
            metadataStatus = .noMetadataFound
            processedWithMetadata = false

            // No metadata available, just copy the file
            try FileManager.default.copyItem(at: mediaFile, to: outputURL)
        }

        // Create and return ProcessingResult
        return ProcessingResult(
            filename: filename,
            originalPath: mediaFile.path,
            metadataStatus: metadataStatus,
            processedWithMetadata: processedWithMetadata,
            outputURL: outputURL
        )
    }

    // Find metadata file trying both suffix variants
    private func findMetadataFile(for mediaFile: URL) throws -> (URL?, String?) {
        let filename = mediaFile.lastPathComponent
        let directory = mediaFile.deletingLastPathComponent()

        // Try correct spelling first: supplemental-metadata.json
        let correctJSONName = filename + ".supplemental-metadata.json"
        let correctJSONURL = directory.appendingPathComponent(correctJSONName)

        if FileManager.default.fileExists(atPath: correctJSONURL.path) {
            return (correctJSONURL, "supplemental-metadata.json")
        }

        // Try variant spelling: supplemental-metadat.json (missing 'a')
        let variantJSONName = filename + ".supplemental-metadat.json"
        let variantJSONURL = directory.appendingPathComponent(variantJSONName)

        if FileManager.default.fileExists(atPath: variantJSONURL.path) {
            return (variantJSONURL, "supplemental-metadat.json")
        }

        // No metadata file found
        return (nil, nil)
    }

    // Find original file metadata for edited versions
    private func findOriginalMetadataForEditedFile(mediaFile: URL, extractedDirectory: URL) throws -> PhotoMetadata? {
        let filename = mediaFile.lastPathComponent

        // Extract base filename by removing "-edited" suffix
        // Example: "IMG_1234-edited.JPG" → "IMG_1234.JPG"
        var baseFilename = filename
        if let editedRange = filename.range(of: "-edited.", options: .caseInsensitive) {
            baseFilename = filename.replacingCharacters(in: editedRange, with: ".")
        }

        // Try to find the original file's metadata with both possible suffixes
        let directory = mediaFile.deletingLastPathComponent()

        // Try correct spelling first: supplemental-metadata.json
        let correctJSONName = baseFilename + ".supplemental-metadata.json"
        let correctJSONURL = directory.appendingPathComponent(correctJSONName)

        if FileManager.default.fileExists(atPath: correctJSONURL.path) {
            let data = try Data(contentsOf: correctJSONURL)
            let decoder = JSONDecoder()
            return try decoder.decode(PhotoMetadata.self, from: data)
        }

        // Try variant spelling: supplemental-metadat.json (missing 'a')
        let variantJSONName = baseFilename + ".supplemental-metadat.json"
        let variantJSONURL = directory.appendingPathComponent(variantJSONName)

        if FileManager.default.fileExists(atPath: variantJSONURL.path) {
            let data = try Data(contentsOf: variantJSONURL)
            let decoder = JSONDecoder()
            return try decoder.decode(PhotoMetadata.self, from: data)
        }

        // If not found in same directory, search the entire extracted structure
        let enumerator = FileManager.default.enumerator(at: extractedDirectory, includingPropertiesForKeys: nil)

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent == correctJSONName {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                return try decoder.decode(PhotoMetadata.self, from: data)
            } else if fileURL.lastPathComponent == variantJSONName {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                return try decoder.decode(PhotoMetadata.self, from: data)
            }
        }

        // Original metadata not found, return nil to use fallback
        return nil
    }

    // Synchronous image processing
    private func processImageSynchronously(
        mediaFile: URL,
        metadata: PhotoMetadata,
        outputURL: URL
    ) throws {
        guard let imageSource = CGImageSourceCreateWithURL(mediaFile as CFURL, nil),
              let imageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw NSError(domain: "ImageProcessingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not create image source"])
        }

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, CGImageSourceGetType(imageSource)!, 1, nil) else {
            throw NSError(domain: "ImageProcessingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not create destination"])
        }

        let exifFormatter = DateFormatter()
        exifFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let exifDateString = exifFormatter.string(from: metadata.takenDate)

        var properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] ?? [:]

        var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        exif[kCGImagePropertyExifDateTimeOriginal] = exifDateString
        exif[kCGImagePropertyExifDateTimeDigitized] = exifDateString
        properties[kCGImagePropertyExifDictionary] = exif

        if metadata.geoData.latitude != 0.0 || metadata.geoData.longitude != 0.0 {
            var gps: [CFString: Any] = [:]
            gps[kCGImagePropertyGPSLatitude] = abs(metadata.geoData.latitude)
            gps[kCGImagePropertyGPSLatitudeRef] = metadata.geoData.latitude >= 0 ? "N" : "S"
            gps[kCGImagePropertyGPSLongitude] = abs(metadata.geoData.longitude)
            gps[kCGImagePropertyGPSLongitudeRef] = metadata.geoData.longitude >= 0 ? "E" : "W"
            gps[kCGImagePropertyGPSAltitude] = metadata.geoData.altitude
            properties[kCGImagePropertyGPSDictionary] = gps
        }

        var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        tiff[kCGImagePropertyTIFFDateTime] = exifDateString
        properties[kCGImagePropertyTIFFDictionary] = tiff

        CGImageDestinationAddImage(destination, imageRef, properties as CFDictionary)

        let success = CGImageDestinationFinalize(destination)
        if !success {
            throw NSError(domain: "ImageProcessingError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to write image with metadata"])
        }
    }

    // MARK: - ZIP Extraction

    private func extractZip(at zipURL: URL, statusCallback: ((String) -> Void)? = nil) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let extractPath = tempDir.appendingPathComponent("extracted")

        do {
            print("🎯 Extracting ZIP: \(zipURL.lastPathComponent)")
            print("📂 Temp extraction path: \(extractPath.path)")

            // Create extraction directory
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: extractPath, withIntermediateDirectories: true)

            // Use ditto command for better Unicode/special character support
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            task.arguments = ["-x", "-k", "--sequesterRsrc", zipURL.path, extractPath.path]
            task.qualityOfService = .userInitiated

            // Capture output for debugging
            let pipe = Pipe()
            let errorPipe = Pipe()
            task.standardOutput = pipe
            task.standardError = errorPipe

            print("🚀 Starting ditto extraction process...")
            print("📝 Command: ditto -x -k --sequesterRsrc \(zipURL.path) \(extractPath.path)")

            do {
                try task.run()
                task.waitUntilExit()

                if task.terminationStatus == 0 {
                    print("✅ Ditto extraction succeeded")

                    // Read and print output for debugging
                    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let outputStr = String(data: outputData, encoding: .utf8), !outputStr.isEmpty {
                        print("📄 Ditto output: \(outputStr)")
                    }

                    // Verify extraction worked
                    let contents = try fileManager.contentsOfDirectory(atPath: extractPath.path)
                    print("📁 Extracted files: \(contents)")

                    return extractPath
                } else {
                    // Read error output
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown ditto error"

                    print("❌ Ditto failed with status \(task.terminationStatus)")
                    print("🔍 Error output: \(errorMessage)")

                    throw NSError(domain: "ZIPExtractionError", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "ditto extraction error: \(errorMessage)"])
                }
            } catch {
                print("💥 Process execution error: \(error)")
                throw error
            }

        } catch {
            print("💥 Final extraction error: \(error)")
            // Clean up temp directory on failure
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }
    }

    // MARK: - Directory Processing

    private func processExtractedFiles(at directory: URL, outputDirectory: URL, zipID: UUID, progressCallback: @escaping (UUID, Double, Int, Int) -> Void, statusCallback: ((String) -> Void)? = nil, fileCallback: ((String) -> Void)? = nil) async throws -> String {
        var filesProcessed = 0
        let mediaFiles = findMediaFiles(in: directory)

        statusCallback?("Found \(mediaFiles.count) media files to process")
        // Update progress with extraction complete, found media files
        progressCallback(zipID, 0.0, mediaFiles.count, 0)

        for (_, mediaFile) in mediaFiles.enumerated() {
            let filename = mediaFile.lastPathComponent
            fileCallback?(filename)

            do {
                try await processMediaFile(mediaFile: mediaFile, outputDirectory: outputDirectory, extractedDirectory: directory)
                filesProcessed += 1

                // Update progress with each file processed
                let progress = Double(filesProcessed) / Double(mediaFiles.count)
                progressCallback(zipID, progress, mediaFiles.count, filesProcessed)
            } catch {
                // Skip this file and continue with others
                print("Error processing \(mediaFile.lastPathComponent): \(error)")
                filesProcessed += 1  // Still count as processed for progress
                progressCallback(zipID, Double(filesProcessed) / Double(mediaFiles.count), mediaFiles.count, filesProcessed)
            }
        }

        statusCallback?("ZIP processing completed: \(filesProcessed)/\(mediaFiles.count) files processed")

        // Clean up temp directory
        try? FileManager.default.removeItem(at: directory)

        return "Processed \(filesProcessed) / \(mediaFiles.count) files"
    }

    private func findMediaFiles(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        var mediaFiles: [URL] = []

        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            let fileExtension = fileURL.pathExtension.lowercased()
            if supportedImageExtensions.contains(fileExtension) || supportedVideoExtensions.contains(fileExtension) {
                mediaFiles.append(fileURL)
            }
        }

        return mediaFiles
    }

    // MARK: - Media File Processing

    private func processMediaFile(mediaFile: URL, outputDirectory: URL, extractedDirectory: URL) async throws {
        // Find corresponding JSON metadata file
        // Google Photos format: filename.ext.supplemental-metadata.json
        // For DSCN2446.JPG, this gives: DSCN2446.JPG.supplemental-metadata.json
        var jsonFileName = mediaFile.lastPathComponent
        // Add the supplemental-metadata extension to the existing filename
        jsonFileName += ".supplemental-metadata.json"
        let jsonURL = mediaFile.deletingLastPathComponent().appendingPathComponent(jsonFileName)

        // Calculate relative path from extracted directory to preserve folder structure
        // Files are extracted to: /temp/uuid/extracted/Takeout/Google Photos/...
        // We want the relative path starting from: Takeout/Google Photos/...

        let mediaFilePath = mediaFile.path

        // Find the position of "Takeout" in the path and extract everything after it
        let components = mediaFilePath.components(separatedBy: "/")

        // Calculate the cleaned relative path
        var cleanedRelativePath = mediaFile.lastPathComponent // fallback
        if let takeoutIndex = components.firstIndex(of: "Takeout") {
            // Take all components from "Takeout" onwards and reconstruct the relative path
            let relativeComponents = components[takeoutIndex..<components.count]
            cleanedRelativePath = relativeComponents.joined(separator: "/")
        }

        // Create output URL preserving directory structure
        let outputURL = outputDirectory.appendingPathComponent(cleanedRelativePath)

        // Create output directory if needed (preserve folder hierarchy)
        let outputDir = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Set proper attributes to ensure visibility in Finder
        let currentDate = Date()
        let attributes = [
            FileAttributeKey.creationDate: currentDate,
            FileAttributeKey.modificationDate: currentDate
        ] as [FileAttributeKey: Any]

        try FileManager.default.setAttributes(attributes, ofItemAtPath: outputDir.path)

        // Also ensure parent directories are visible
        var parentDir = outputDir
        for _ in 0..<3 { // Check a few parent levels
            parentDir = parentDir.deletingLastPathComponent()
            if parentDir.path != outputDirectory.path {
                do {
                    try FileManager.default.setAttributes(attributes, ofItemAtPath: parentDir.path)
                } catch {
                    break // Stop when we can't access further parents
                }
            }
        }

        // Try to set proper permissions using chmod-like approach for better Finder visibility
        // This is a sandbox-compatible attempt to ensure visibility
        let fileManager = FileManager.default
        try fileManager.setAttributes([
            FileAttributeKey.posixPermissions: NSNumber(value: 0o755)
        ], ofItemAtPath: outputDir.path)

        let fileExtension = mediaFile.pathExtension.lowercased()

        // Check if we have metadata for this file
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            print("✅ Found metadata file for: \(mediaFile.lastPathComponent)")
            do {
                // Parse metadata and process with EXIF data
                let metadata = try await parseMetadata(from: jsonURL)

                // Process based on file type
                if supportedImageExtensions.contains(fileExtension) {
                    print("🖼️ Processing image with metadata: \(mediaFile.lastPathComponent)")
                    try await processImage(mediaFile: mediaFile, metadata: metadata, outputURL: outputURL)
                } else if supportedVideoExtensions.contains(fileExtension) {
                    print("🎬 Processing video with metadata: \(mediaFile.lastPathComponent)")
                    try await processVideo(mediaFile: mediaFile, metadata: metadata, outputURL: outputURL)
                }

                // Update file timestamps from metadata
                try updateFileTimestamps(at: outputURL, date: metadata.takenDate)
                print("✅ Metadata processing completed for: \(mediaFile.lastPathComponent)")

                // Remove JSON file
                try? FileManager.default.removeItem(at: jsonURL)
            } catch {
                print("❌ Error processing metadata for \(mediaFile.lastPathComponent): \(error)")
                // Fall back to copying without metadata
                try FileManager.default.copyItem(at: mediaFile, to: outputURL)
            }
        } else {
            // No metadata found - just copy the file as-is
            print("📝 No metadata file found for: \(mediaFile.lastPathComponent) - copying file without EXIF data")
            try FileManager.default.copyItem(at: mediaFile, to: outputURL)
        }
    }

    private func parseMetadata(from jsonURL: URL) async throws -> PhotoMetadata {
        let data = try Data(contentsOf: jsonURL)
        let decoder = JSONDecoder()
        return try decoder.decode(PhotoMetadata.self, from: data)
    }

    // MARK: - Image Processing

    private func processImage(mediaFile: URL, metadata: PhotoMetadata, outputURL: URL) async throws {
        guard let imageSource = CGImageSourceCreateWithURL(mediaFile as CFURL, nil) else {
            throw NSError(domain: "ImageProcessingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not create image source"])
        }

        guard let imageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw NSError(domain: "ImageProcessingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not create image"])
        }

        // Create destination
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, CGImageSourceGetType(imageSource)!, 1, nil) else {
            throw NSError(domain: "ImageProcessingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not create destination"])
        }

        // Format date for EXIF (YYYY:MM:DD HH:MM:SS)
        let exifFormatter = DateFormatter()
        exifFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let exifDateString = exifFormatter.string(from: metadata.takenDate)

        // Get the original properties and modify them instead of creating new ones
        // This ensures we override the original metadata rather than merging
        var properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] ?? [:]

        // Override EXIF metadata with metadata from JSON - main capture time
        var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        exif[kCGImagePropertyExifDateTimeOriginal] = exifDateString
        exif[kCGImagePropertyExifDateTimeDigitized] = exifDateString
        properties[kCGImagePropertyExifDictionary] = exif

        // Override GPS metadata with metadata from JSON (if available)
        if metadata.geoData.latitude != 0.0 || metadata.geoData.longitude != 0.0 {
            print("📍 Adding GPS data: lat=\(metadata.geoData.latitude), lon=\(metadata.geoData.longitude)")
            var gps: [CFString: Any] = [:]
            gps[kCGImagePropertyGPSLatitude] = abs(metadata.geoData.latitude)
            gps[kCGImagePropertyGPSLatitudeRef] = metadata.geoData.latitude >= 0 ? "N" : "S"
            gps[kCGImagePropertyGPSLongitude] = abs(metadata.geoData.longitude)
            gps[kCGImagePropertyGPSLongitudeRef] = metadata.geoData.longitude >= 0 ? "E" : "W"
            gps[kCGImagePropertyGPSAltitude] = metadata.geoData.altitude
            properties[kCGImagePropertyGPSDictionary] = gps
        }

        // Override TIFF metadata with metadata from JSON - file creation time
        var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        tiff[kCGImagePropertyTIFFDateTime] = exifDateString
        properties[kCGImagePropertyTIFFDictionary] = tiff

        // Write the image
        print("📝 Writing image with overridden metadata to: \(outputURL.path)")
        CGImageDestinationAddImage(destination, imageRef, properties as CFDictionary)

        let success = CGImageDestinationFinalize(destination)
        if success {
            print("✅ Image metadata write successful")
            // Verify metadata was written
            try await verifyMetadataWritten(to: outputURL)
        } else {
            throw NSError(domain: "ImageProcessingError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to write image with metadata"])
        }
    }

    private func verifyMetadataWritten(to url: URL) async throws {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw NSError(domain: "VerificationError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not verify written image"])
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            print("⚠️ No properties found in written image")
            return
        }

        // Check EXIF metadata
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let dateTimeOriginal = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            print("✅ Verified EXIF DateTimeOriginal: \(dateTimeOriginal)")
        } else {
            print("⚠️ No EXIF DateTimeOriginal found in written image")
        }

        // Check GPS metadata
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let latitude = gps[kCGImagePropertyGPSLatitude] as? Double {
            print("✅ Verified GPS data: lat=\(latitude)")
        }
    }

    // MARK: - Video Processing

    private func processVideo(mediaFile: URL, metadata: PhotoMetadata, outputURL: URL) async throws {
        // For videos, we'll create a new file with updated metadata
        let data = try Data(contentsOf: mediaFile)
        try data.write(to: outputURL)

        // Note: For more comprehensive video metadata handling, you might want to use AVFoundation
        // to write metadata to specific tracks. This is a simplified version that just copies the file.
        // In a production app, you'd want to:
        // 1. Create AVAssetReader/AVAssetWriter
        // 2. Copy all tracks with metadata modifications
        // 3. Set creation date metadata on the asset
    }

    // MARK: - File Operations

    private func updateFileTimestamps(at url: URL, date: Date) throws {
        let attributes = [FileAttributeKey.creationDate: date, FileAttributeKey.modificationDate: date]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
    }
}
