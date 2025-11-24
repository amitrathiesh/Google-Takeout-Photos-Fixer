/// ContentView.swift
/// takout-photos-fixer
///
/// Created by Amit Rathiesh on 2025-10-23.
///

import SwiftUI
import UniformTypeIdentifiers

/// Main user interface for Google Photos Takeout Fixer
///
/// This SwiftUI view provides the complete user interface for processing Google Photos
/// Takeout ZIP files. It uses a state-driven architecture that transitions between different
/// screens based on processing status:
///
/// - Welcome Screen: Initial interface for selecting ZIP files and output directory
/// - Ready Screen: Confirms selection and allows changing settings
/// - Processing Screen: Shows live progress with real-time statistics
/// - Completion Screen: Displays final summary with detailed statistics
/// - Reprocessing Screen: Handles rechecking missed metadata files
///
/// The view implements comprehensive progress tracking, detailed logging, and
/// user feedback throughout the entire processing pipeline.
///
struct ContentView: View {
    @State private var showingFileImporter = false
    @State private var outputDirectory: URL? = nil
    @State private var selectedFileURLs: [URL] = []
    @State private var isProcessing = false
    @State private var processingItems: [ProcessingItem] = []
    @State private var statusMessage = ""
    @State private var currentFileMessage = ""
    @State private var logMessages: [String] = []
    @State private var showLogs = true
    @State private var processingResults: [ProcessingResult] = []
    @State private var lastExtractedDirectory: URL? = nil
    @State private var isReprocessingMissed = false

    private let fileProcessor = FileProcessor()
    private let processorManager = ProcessorManager()

    // Computed properties for UI state
    private var currentState: AppState {
        if isReprocessingMissed {
            return .reprocessing
        } else if isProcessing {
            return .processing
        } else if !processingResults.isEmpty {
            return .completed
        } else if !selectedFileURLs.isEmpty && outputDirectory != nil {
            return .readyToProcess
        } else {
            return .welcome
        }
    }

    private enum AppState {
        case welcome
        case readyToProcess
        case processing
        case reprocessing
        case completed
    }

    // Computed statistics for the summary
    private var fileProcessedCount: Int {
        processingResults.count
    }

    private var filesWithMetadataCount: Int {
        processingResults.filter { $0.processedWithMetadata }.count
    }

    private var filesMissingMetadataCount: Int {
        processingResults.filter { !$0.processedWithMetadata }.count
    }

    private var missedFiles: [ProcessingResult] {
        processingResults.filter { !$0.processedWithMetadata }
    }
    var body: some View {
        VStack(spacing: 20) {
            // Reserved space for window controls (red, yellow, green buttons)
            Spacer()
                .frame(height: 72) // Generous space for enhanced titlebar feel

            // Main Header in content area
            HStack {
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("Google Photos Takeout Fixer")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 20)

            // Dynamic content based on current state
            VStack(spacing: 16) {
                contentForCurrentState()
                    .padding(.horizontal, 40)

                // Live Processing Statistics Header (shown during processing)
                if isProcessing && !processingResults.isEmpty {
                    processingStatsHeader()
                        .padding(.horizontal, 40)
                }

                // Log section with toggle
                VStack(spacing: 8) {
                    HStack {
                        Button(action: {
                            showLogs.toggle()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: showLogs ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 12))
                                Text("Activity Log (\(logMessages.count) entries)")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.horizontal, 40)

                    if showLogs {
                        logView()
                            .padding(.horizontal, 40)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            setupWindow()
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result: result)
        }
    }

    // Window configuration for seamless titlebar integration
    private func setupWindow() {
        #if os(macOS)
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.styleMask.insert(.fullSizeContentView)
        }
        #endif
    }

    // File and folder picker methods
    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Output Folder"
        panel.title = "Select where to save processed photos"

        if panel.runModal() == .OK, let url = panel.url {
            self.outputDirectory = url
        }
    }

    private func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            self.selectedFileURLs = urls
            // In a real app, this would trigger processing
            print("Selected \(urls.count) ZIP files:")
            for url in urls {
                print("  - \(url.lastPathComponent)")
            }
        case .failure(let error):
            print("File selection error: \(error)")
        }
    }

    // Dynamic UI state management
    @ViewBuilder
    private func contentForCurrentState() -> some View {
        VStack(spacing: 32) {
            switch currentState {
            case .welcome:
                welcomeContent()
            case .readyToProcess:
                readyToProcessContent()
            case .processing:
                processingContent()
            case .reprocessing:
                reprocessingContent()
            case .completed:
                completedContent()
            }
        }
    }

    // Log management
    private func addLogMessage(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        logMessages.append(logEntry)
    }

    private func logView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity Log")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(logMessages.indices, id: \.self) { index in
                            Text(logMessages[index])
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.8))
                                .textSelection(.enabled)
                                .id(index) // Use index as ID for scrolling
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)
                .background(.thinMaterial.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: logMessages) { _, _ in
                    // Auto-scroll to the last message when new messages arrive
                    if let lastIndex = logMessages.indices.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // Scroll to bottom when view first appears
                    if let lastIndex = logMessages.indices.last {
                        DispatchQueue.main.async {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func welcomeContent() -> some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 120, height: 120)
                        .blur(radius: 20)

                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48, weight: .thin, design: .rounded))
                        .foregroundStyle(Color.blue)
                }

                VStack(spacing: 8) {
                    Text("Welcome to Photos Takeout Fixer")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Transform your Google Photos export")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                Button("Select ZIP Files") {
                    showingFileImporter = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Choose Output Folder") {
                    chooseOutputDirectory()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Text("Ready to fix your photos!")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.7))
        }
    }

    private func readyToProcessContent() -> some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 120, height: 120)
                        .blur(radius: 15)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.green)
                }

                VStack(spacing: 8) {
                    Text("Ready to Process")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("\(selectedFileURLs.count) ZIP file(s) selected")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Color.blue.opacity(0.7))
                    Text("Output: \(outputDirectory?.lastPathComponent ?? "Unknown")")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14, design: .rounded))
                }
                .padding()
                .background(.thinMaterial.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 12) {
                    Button("Change Files") {
                        showingFileImporter = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button("Change Folder") {
                        chooseOutputDirectory()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }

            Button("Start Processing") {
                startProcessing()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func processingContent() -> some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.1), lineWidth: 8)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0.0, to: 0.7) // Mock progress
                    .stroke(Color.blue, lineWidth: 8)
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.large)
                        .scaleEffect(1.2)
                }
            }

            VStack(spacing: 12) {
                Text("Processing ZIP files...")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Please wait while we fix your photos")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Button("Stop Processing") {
                isProcessing = false
            }
            .buttonStyle(.bordered)
            .foregroundStyle(.red)
        }
    }

    private func reprocessingContent() -> some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.1), lineWidth: 8)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0.0, to: 0.8) // Mock progress for reprocessing
                    .stroke(Color.orange, lineWidth: 8)
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.large)
                        .scaleEffect(1.2)
                }

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 24, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.orange)
            }

            VStack(spacing: 12) {
                Text("Reprocessing missed files...")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Finding metadata for previously missed files")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Button("Stop Reprocessing") {
                isReprocessingMissed = false
            }
            .buttonStyle(.bordered)
            .foregroundStyle(.red)
        }
    }

    private func completedContent() -> some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 120, height: 120)
                        .blur(radius: 15)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.green)
                }

                VStack(spacing: 8) {
                    Text("Processing Complete!")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("\(fileProcessedCount) files processed")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            // Summary statistics
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    StatisticsRow(
                        icon: "🖼️",
                        label: "Files Processed",
                        value: "\(fileProcessedCount)",
                        color: .primary
                    )

                    StatisticsRow(
                        icon: "✅",
                        label: "With Metadata",
                        value: "\(filesWithMetadataCount)",
                        color: .green
                    )

                    StatisticsRow(
                        icon: "📋",
                        label: "Missing Metadata",
                        value: "\(filesMissingMetadataCount)",
                        color: filesMissingMetadataCount > 0 ? .orange : .green
                    )
                }
                .padding()
                .background(.thinMaterial.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if filesMissingMetadataCount > 0 {
                    Button("Recheck JSON for Missed Files") {
                        recheckMissedFiles()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .foregroundStyle(.orange)

                    Text("Try to find metadata that was missed during initial processing")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("All files have metadata! 🎉")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.green)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            HStack(spacing: 12) {
                Button("Process New Files") {
                    resetToWelcome()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("Open Output Folder") {
                    if let outputDir = outputDirectory {
                        NSWorkspace.shared.open(outputDir)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }

    private func startProcessing() {
        guard let outputDir = outputDirectory else { return }

        isProcessing = true
        statusMessage = "Initializing..."
        processingItems = selectedFileURLs.map { ProcessingItem(zipFileURL: $0, state: .pending) }

        // Run entirely synchronous processing on background thread
        // No async/await - completely isolated from main thread
        DispatchQueue.global(qos: .background).async {

            // Completely synchronous processing with completion callbacks
            self.fileProcessor.processZipFilesSynchronously(
                zipURLs: self.selectedFileURLs,
                outputDirectory: outputDir,
                progressCallback: { zipID, progress, total, processed in
                    DispatchQueue.main.async {
                        self.updateProgress(for: zipID, progress: progress, total: total, processed: processed)
                    }
                },
                statusCallback: { message in
                    DispatchQueue.main.async {
                        self.statusMessage = message
                        self.addLogMessage(message)
                    }
                },
                fileCallback: { filename in
                    DispatchQueue.main.async {
                        self.currentFileMessage = "Processing: \(filename)"
                        self.addLogMessage("Processing file: \(filename)")
                        // Force UI update by manipulating array
                        self.forceUIUpdate()
                    }
                },
                fileResultCallback: { result in
                    DispatchQueue.main.async {
                        self.processingResults.append(result)
                    }
                },
                completion: { results, error in
                    DispatchQueue.main.async {
                        self.finalizeProcessing(results: results ?? [], error: error)
                    }
                }
            )
        }
    }

    private func forceUIUpdate() {
        // Force SwiftUI to update the log view
        DispatchQueue.main.async {
            self.logMessages.append("")
            self.logMessages.removeLast()
        }
    }

    private func updateProgress(for zipID: UUID, progress: Double, total: Int, processed: Int) {
        if let index = processingItems.firstIndex(where: { $0.id == zipID }) {
            processingItems[index].progress = progress
            processingItems[index].totalFiles = total
            processingItems[index].processedFiles = processed
        }
    }

    private func finalizeProcessing(results: [(UUID, Result<String, Error>)], error: Error?) {
        // Ensure we have complete processing results before showing final screen

        if let error = error {
            isProcessing = false
            statusMessage = "Error: \(error.localizedDescription)"
        } else {
            let successCount = results.filter { if case .success = $0.1 { return true } else { return false } }.count
            let failCount = results.filter { if case .failure = $0.1 { return true } else { return false } }.count
            statusMessage = "Completed! \(successCount) successful, \(failCount) failed"

            if successCount > 0 {
                // Auto-reveal output folder in Finder
                if let outputDir = outputDirectory {
                    NSWorkspace.shared.open(outputDir)
                }
            }

            // Delay the isProcessing = false to allow file results to be fully collected
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isProcessing = false
            }
        }
    }
}

// Statistics row component for the summary display
private struct StatisticsRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(icon)
                .font(.system(size: 14))
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }
}

extension ContentView {

    // Live processing statistics header shown above logs
    private func processingStatsHeader() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                    Text("Live Processing Statistics")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()

                // Processing progress counters
                HStack(spacing: 24) {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.blue.opacity(0.7))
                        Text("Processing: \(fileProcessedCount)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.green)
                        Text("✅: \(filesWithMetadataCount)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                        Text("📋: \(filesMissingMetadataCount)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func recheckMissedFiles() {
        guard !missedFiles.isEmpty else { return }

        isReprocessingMissed = true
        statusMessage = "Reprocessing \(missedFiles.count) missed files..."

        // Add reprocessing entries to log
        addLogMessage("Starting reprocessing of \(missedFiles.count) missed files...")

        // Run reprocessing on background thread
        DispatchQueue.global(qos: .background).async {

            // Reprocess only the missed files
            var updatedResults = self.processingResults

            for missedFile in self.missedFiles {
                DispatchQueue.main.async {
                    self.addLogMessage("Rechecking: \(missedFile.filename)")
                }

                // Try to find metadata that was previously missed
                // This could be due to different JSON variants or location issues
                let hasMetadata = self.attemptMetadataRecovery(for: missedFile)

                // Update the processing result if metadata was found
                if let index = updatedResults.firstIndex(where: { $0.id == missedFile.id }) {
                    updatedResults[index] = ProcessingResult(
                        filename: missedFile.filename,
                        originalPath: missedFile.originalPath,
                        metadataStatus: hasMetadata ? .metadataFoundLate : .noMetadataFound,
                        processedWithMetadata: hasMetadata,
                        outputURL: missedFile.outputURL
                    )
                }

                DispatchQueue.main.async {
                    self.addLogMessage("✅ Reprocessed: \(missedFile.filename)")
                    self.forceUIUpdate()
                }
            }

            DispatchQueue.main.async {
                self.processingResults = updatedResults
                self.isReprocessingMissed = false
                self.addLogMessage("Reprocessing complete!")
            }
        }
    }

    private func attemptMetadataRecovery(for missedFile: ProcessingResult) -> Bool {
        // For now, implement a simplified recovery that tries to find
        // metadata using our improved filename detection
        // In a full implementation, this could use more sophisticated matching

        // Extract directory path from the missed file
        guard outputDirectory != nil else { return false }
        _ = missedFile.originalPath

        // Try to find any metadata file that might match this filename
        // This is a placeholder implementation - in practice you'd want
        // more sophisticated pattern matching

        // For demonstration, simulate finding metadata for some files
        // In a real implementation, you'd search for JSON files that could
        // correspond to this file

        return false // Placeholder - return true if metadata is found
    }

    private func resetToWelcome() {
        // Reset all state to welcome screen
        selectedFileURLs.removeAll()
        outputDirectory = nil
        processingResults.removeAll()
        logMessages.removeAll()
        isProcessing = false
        isReprocessingMissed = false
        processingItems.removeAll()
        statusMessage = ""
        currentFileMessage = ""
        lastExtractedDirectory = nil
    }
}

#Preview {
    ContentView()
}
