/// PhotoMetadata.swift
/// takout-photos-fixer
///
/// Data models and processing states for Google Photos Takeout fixer application.
///
/// This file contains:
/// - JSON parsing models for Google Photos metadata
/// - Processing state management for ZIP file operations
/// - Data structures for tracking processing progress and results
/// - Asynchronous task management using Swift actors
///
/// All models conform to Codable for JSON serialization and provide
/// computed properties for convenient data access.
///

import Foundation

/// Represents the JSON metadata structure from Google Photos Takeout exports
///
/// Google Photos Takeout provides a supplemental-metadata.json file for each photo/video
/// containing detailed information about capture time, location, and other metadata.
/// This structure matches the JSON schema used by Google's export service.
///
struct PhotoMetadata: Codable {
    let title: String
    let description: String?
    let imageViews: String?
    let creationTime: TimeInfo
    let photoTakenTime: TimeInfo
    let geoData: GeoData
    let people: [Person]?
    let url: String?

    // Nested structs
    struct TimeInfo: Codable {
        let timestamp: String
        let formatted: String
    }

    struct GeoData: Codable {
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let latitudeSpan: Double?
        let longitudeSpan: Double?
    }

    struct Person: Codable {
        let name: String
    }

    // Helper to get photoTakenTime as Date
    var takenDate: Date {
        return Date(timeIntervalSince1970: Double(photoTakenTime.timestamp) ?? 0)
    }
}

// Model for processing status
enum ProcessingState {
    case pending
    case processing
    case completed
    case error(String)
}

// Model for zip file processing
struct ProcessingItem: Identifiable {
    let id = UUID()
    let zipFileURL: URL
    var state: ProcessingState
    var progress: Double = 0.0
    var totalFiles: Int = 0
    var processedFiles: Int = 0
}

// Model for individual file processing results
struct ProcessingResult: Identifiable {
    let id = UUID()
    let filename: String
    let originalPath: String // Path in extracted ZIP for reprocessing
    let metadataStatus: MetadataStatus
    let processedWithMetadata: Bool
    let outputURL: URL?

    enum MetadataStatus: String {
        case foundAndApplied = "metadata_applied"
        case inheritedFromOriginal = "inherited_from_original"
        case noMetadataFound = "no_metadata"
        case metadataFoundLate = "metadata_found_late" // For reprocessing
    }

    var description: String {
        switch metadataStatus {
        case .foundAndApplied:
            return "✅ Metadata applied"
        case .inheritedFromOriginal:
            return "🔗 Inherited from original"
        case .noMetadataFound:
            return "📋 No metadata found"
        case .metadataFoundLate:
            return "✅ Metadata found on recheck"
        }
    }
}

actor ProcessorManager {
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    func addProcessingTask(id: UUID, task: Task<Void, Never>) {
        activeTasks[id] = task
    }

    func cancelTask(id: UUID) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
    }

    func cancelAll() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
    }
}
