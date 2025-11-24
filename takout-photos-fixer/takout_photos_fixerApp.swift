//
//  takout_photos_fixerApp.swift
//  takout-photos-fixer
//
//  Created by Amit Rathiesh on 2025-10-23.
//

import SwiftUI

/// Main application entry point for Google Photos Takeout Fixer
///
/// This macOS application processes Google Photos Takeout ZIP files by:
/// - Extracting and merging multiple ZIP files
/// - Applying JSON metadata to corresponding media files
/// - Providing comprehensive progress tracking and user feedback
/// - Supporting reprocessing for missed metadata
///
@main
struct takout_photos_fixerApp: App {

    /// The main application scene configuration
    ///
    /// Creates a single window group containing the ContentView,
    /// which manages the entire application interface and processing logic.
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
