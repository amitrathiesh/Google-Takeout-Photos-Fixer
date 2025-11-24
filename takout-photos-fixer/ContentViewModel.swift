import SwiftUI
import Combine
import UniformTypeIdentifiers


@MainActor
class ContentViewModel: ObservableObject {
    @Published var processingItems: [ProcessingItem] = []
    @Published var showingFileImporter = false
    @Published var showingFileExporter = false
    @Published var hasSelectedFiles = false
    @Published var isProcessing = false
    @Published var exportDocument: EmptyFile? = nil
    @Published var outputDirectory: URL? = nil
    @Published var currentStatusMessage: String = "Ready to process"
    @Published var currentFileBeingProcessed: String = ""
    @Published var detailedLog: [String] = []
    @Published var overallProgress: Double = 0.0
    @Published var filesProcessed: Int = 0
    @Published var totalFiles: Int = 0
    @Published var showCompletionHelper: Bool = false
    private var processor = FileProcessor()
    private var processorManager = ProcessorManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Public Interface

    func showFilePicker() {
        showingFileImporter = true
    }

    func handleFileImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let validURLs = urls.filter { url in
                url.pathExtension.lowercased() == "zip"
            }

            createProcessingItems(from: validURLs)
            hasSelectedFiles = true

        case .failure(let error):
            print("File selection error: \(error)")
        }
    }

    func handleExportResult(result: Result<URL, any Error>) {
        // Store chosen output directory
        switch result {
        case .success(let url):
            self.outputDirectory = url
        case .failure(let error):
            print("Directory selection error: \(error)")
        }
        showingFileExporter = false
    }

    func chooseOutputDirectory() {
        // For now, just open a basic directory picker
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

    func startProcessing() {
        currentStatusMessage = "Initializing..."
        if outputDirectory == nil {
            // Use default directory if none chosen
            requestOutputDirectory()
        } else {
            // Start processing with chosen directory
            performProcessing()
        }
    }

    func getOutputDirectoryPath() -> String {
        if let dir = outputDirectory {
            return dir.lastPathComponent
        } else {
            return "Takeout Photos Fixed (in Downloads)"
        }
    }

    func stopProcessing() {
        Task {
            await processorManager.cancelAll()
        }

        for i in processingItems.indices {
            if case .processing = processingItems[i].state {
                processingItems[i].state = .error("Cancelled")
                processingItems[i].progress = 0
            }
        }

        isProcessing = false
    }

    func openOutputFolder() {
        guard let outputDirectory = outputDirectory else { return }

        NSWorkspace.shared.open(outputDirectory)
    }

    func dismissCompletionHelper() {
        showCompletionHelper = false
    }

    // MARK: - Private Methods

    private func createProcessingItems(from zipURLs: [URL]) {
        processingItems = zipURLs.map { url in
            ProcessingItem(zipFileURL: url, state: .pending, progress: 0.0, totalFiles: 0, processedFiles: 0)
        }
    }

    private func requestOutputDirectory() {
        // Create default directory
        do {
            let tempDir = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                .appendingPathComponent("Takeout Photos Fixed", isDirectory: true)

            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            outputDirectory = tempDir
            performProcessing()
        } catch {
            print("Failed to create output directory: \(error)")
        }
    }

    private func performProcessing() {
        guard let outputDirectory = outputDirectory, !processingItems.isEmpty else { return }

        isProcessing = true

        Task {
            do {
                let zipURLs = processingItems.map { $0.zipFileURL }

                // Calculate total files across all ZIPs for overall progress
                // File count will be determined during processing via progress callbacks

                // Create progress callback handler
                let progressHandler: (UUID, Double, Int, Int) -> Void = { uuid, progress, total, processed in
                    DispatchQueue.main.async {
                        if let index = self.processingItems.indices.first(where: { self.processingItems[$0].id == uuid }) {
                            self.processingItems[index].progress = progress
                            self.processingItems[index].totalFiles = total
                            self.processingItems[index].processedFiles = processed

                            // Update overall progress
                            var overallProcessed = 0
                            var overallTotal = 0
                            for item in self.processingItems {
                                overallProcessed += item.processedFiles
                                overallTotal += item.totalFiles
                            }
                            self.filesProcessed = overallProcessed
                            self.totalFiles = overallTotal
                            if overallTotal > 0 {
                                self.overallProgress = Double(overallProcessed) / Double(overallTotal)
                            }

                            // Update state based on progress
                            if progress > 0 && self.processingItems[index].state == .pending {
                                self.processingItems[index].state = .processing
                                self.currentStatusMessage = "Processing \(self.processingItems[index].zipFileURL.lastPathComponent)..."
                            } else if progress >= 1.0 {
                                self.processingItems[index].state = .completed
                            }
                        }
                    }
                }

                // Status message callback
                let statusCallback: (String) -> Void = { status in
                    DispatchQueue.main.async {
                        self.currentStatusMessage = status
                    }
                }

                // File processing callback
                let fileCallback: (String) -> Void = { filename in
                    DispatchQueue.main.async {
                        self.currentFileBeingProcessed = filename
                        self.detailedLog.append("Processing: \(filename)")
                        // Keep only last 10 log entries for UI performance
                        if self.detailedLog.count > 10 {
                            self.detailedLog.removeFirst()
                        }
                    }
                }

                let results = try await processor.processZipFiles(zipURLs: zipURLs, outputDirectory: outputDirectory, progressCallback: progressHandler, statusCallback: statusCallback, fileCallback: fileCallback)

                // Update final states
                DispatchQueue.main.async {
                    for (uuid, result) in results {
                        if let index = self.processingItems.indices.first(where: { self.processingItems[$0].id == uuid }) {
                            switch result {
                            case .success(_):
                                self.processingItems[index].state = .completed
                                self.processingItems[index].processedFiles = self.processingItems[index].totalFiles
                            case .failure(let error):
                                self.processingItems[index].state = .error(error.localizedDescription)
                            }
                        }
                    }

                    // Final completion message
                    self.currentStatusMessage = "✅ Processing Complete! All ZIP files have been processed."
                    self.detailedLog.append("🎉 Processing completed successfully!")
                    self.detailedLog.append("📁 Output folder: \(self.getOutputDirectoryPath())")
                    self.detailedLog.append("📊 Final results: \(self.totalFiles) files processed")
                    self.filesProcessed = self.totalFiles // Ensure overall completion

                    self.isProcessing = false
                }

            } catch {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    for i in self.processingItems.indices {
                        if case .processing = self.processingItems[i].state {
                            self.processingItems[i].state = .error(error.localizedDescription)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Helper Types

struct EmptyFile: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }

    init() {}

    init(configuration: Self.ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}

// MARK: - Extensions

extension ProcessingState: Equatable {
    static func == (lhs: ProcessingState, rhs: ProcessingState) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending): return true
        case (.processing, .processing): return true
        case (.completed, .completed): return true
        case (.error(let lhsError), .error(let rhsError)): return lhsError == rhsError
        default: return false
        }
    }
}
