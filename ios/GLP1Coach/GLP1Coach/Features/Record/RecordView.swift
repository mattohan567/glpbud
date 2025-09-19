import SwiftUI
import PhotosUI
import AVFoundation
import Speech

struct RecordView: View {
    let initialTab: Int
    @State private var selectedTab = 0

    init(initialTab: Int = 0) {
        self.initialTab = initialTab
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            // Extend background to fill entire screen including bottom area
            AppBackground()
                .ignoresSafeArea(.all)

            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.spacing.lg) {
                    // Hero Title
                    Text("Record")
                        .font(.heroTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Tab Selector
                    GlassCard {
                        PillSegment(items: ["Meal", "Exercise", "Weight"], selection: $selectedTab)
                    }

                    // Content based on selected tab
                    Group {
                        switch selectedTab {
                        case 0:
                            UnifiedMealRecordView()
                        case 1:
                            UnifiedExerciseRecordView()
                        case 2:
                            WeightRecordContent()
                        default:
                            EmptyView()
                        }
                    }
                }
                .padding()
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Audio Player Delegate
class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }
}

// MARK: - Unified Meal Recording with Text, Photo, and Audio
struct UnifiedMealRecordView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @State private var mealText = ""
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var showingCamera = false
    @State private var showingPhotoActionSheet = false
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var hasRecordingPermission = false
    @State private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine = AVAudioEngine()
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var audioPlayerDelegate = AudioPlayerDelegate()
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        VStack(spacing: Theme.spacing.lg) {
            // Main text input area
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.spacing.md) {
                    Text("Describe your meal")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)

                    TextEditor(text: $mealText)
                        .frame(minHeight: 120)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .background(Color.black.opacity(0.3))
                        .foregroundStyle(.white)
                        .tint(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius.sm, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .focused($isTextEditorFocused)
                        .keyboardToolbar {
                            isTextEditorFocused = false
                        }

                    Text("Example: Grilled chicken breast 200g with rice")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            // Input method buttons
            GlassCard {
                VStack(spacing: Theme.spacing.md) {
                    Text("Quick Input Methods")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: Theme.spacing.md) {
                        // Photo button
                        VStack(spacing: 8) {
                            Button(action: { showingPhotoActionSheet = true }) {
                                VStack(spacing: 8) {
                                    Image(systemName: "camera.fill")
                                        .font(.title)
                                    Text("Photo")
                                        .font(.caption.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.cornerRadius.md, style: .continuous)
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                )
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }

                        // Audio button
                        VStack(spacing: 8) {
                            Button(action: { toggleRecording() }) {
                                VStack(spacing: 8) {
                                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.fill")
                                        .font(.title)
                                        .foregroundStyle(isRecording ? Theme.danger : .white)
                                    Text(isRecording ? "Stop" : "Audio")
                                        .font(.caption.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(isRecording ? Color.red.opacity(0.2) : Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.cornerRadius.md, style: .continuous)
                                        .stroke(isRecording ? Theme.danger.opacity(0.5) : Color.white.opacity(0.25), lineWidth: 1)
                                )
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if isRecording {
                        VStack(spacing: 4) {
                            HStack {
                                Image(systemName: "waveform")
                                    .foregroundStyle(Theme.danger)
                                Text("Recording... Describe what you ate")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            // Show simulator warning
                            #if targetEnvironment(simulator)
                            Text("⚠️ Audio may not work in simulator - use text input")
                                .font(.caption2)
                                .foregroundStyle(Theme.warn)
                            #endif
                        }
                        .padding(.top, 8)
                    }
                }
            }

            // Selected photo preview
            if let image = selectedImage {
                GlassCard {
                    VStack(spacing: Theme.spacing.md) {
                        HStack {
                            Text("Selected Photo")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Button("Change") {
                                showingImagePicker = true
                            }
                            .foregroundStyle(Theme.accent)
                        }

                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.md, style: .continuous))
                    }
                }
            }

            // Audio recording preview
            if recordingURL != nil {
                GlassCard {
                    VStack(spacing: Theme.spacing.md) {
                        HStack {
                            Text("Audio Recording")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Button("Remove") {
                                recordingURL = nil
                            }
                            .foregroundStyle(Theme.danger)
                        }

                        HStack(spacing: Theme.spacing.md) {
                            Image(systemName: "waveform")
                                .font(.title)
                                .foregroundStyle(Theme.accent)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Voice description recorded")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Will be processed with meal analysis")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            Spacer()

                            // Play/Pause button
                            Button(action: { togglePlayback() }) {
                                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.sm, style: .continuous))
                    }
                }
            }

            // Analyze button
            PrimaryButton(
                title: "Analyze & Log Meal",
                isLoading: isLoading
            ) {
                analyzeMeal()
            }
            .disabled(mealText.isEmpty && selectedImage == nil && recordingURL == nil)
        }
        .alert("Meal Logging", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage, sourceType: .photoLibrary)
        }
        .sheet(isPresented: $showingCamera) {
            ImagePicker(image: $selectedImage, sourceType: .camera)
        }
        .confirmationDialog("Add Photo", isPresented: $showingPhotoActionSheet) {
            Button("Take Photo") {
                showingCamera = true
            }
            Button("Choose from Library") {
                showingImagePicker = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .onAppear {
            requestMicrophonePermission()
            requestSpeechPermission()
        }
        .onDisappear {
            // Properly dismiss keyboard and clear focus to prevent session issues
            isTextEditorFocused = false
        }
        .tapToDismissKeyboard()
        .manageKeyboard()
    }

    private func requestMicrophonePermission() {
        // First check current permission status
        let currentStatus = AVAudioSession.sharedInstance().recordPermission

        switch currentStatus {
        case .granted:
            print("🎤 Microphone permission already granted")
            hasRecordingPermission = true
        case .denied:
            print("🎤 Microphone permission denied")
            hasRecordingPermission = false
        case .undetermined:
            print("🎤 Requesting microphone permission...")
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    print("🎤 Microphone permission result: \(granted)")
                    self.hasRecordingPermission = granted
                }
            }
        @unknown default:
            print("🎤 Unknown microphone permission status")
            hasRecordingPermission = false
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        print("🎤 Starting recording - hasRecordingPermission: \(hasRecordingPermission)")

        guard hasRecordingPermission else {
            print("🎤 Recording blocked - no microphone permission")
            alertMessage = "Microphone permission is required for audio recording"
            showingAlert = true
            return
        }

        let audioSession = AVAudioSession.sharedInstance()

        do {
            // Configure audio session with specific options for recording
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try audioSession.setActive(true, options: [])

            print("📱 Audio session configured - Category: \(audioSession.category), Mode: \(audioSession.mode)")

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioURL = documentsPath.appendingPathComponent("meal_recording_\(Date().timeIntervalSince1970).m4a")
            recordingURL = audioURL

            // Use simple, compatible settings that work reliably
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,  // Standard sample rate for better compatibility
                AVNumberOfChannelsKey: 1
                // Removed quality/bitrate settings that were causing conflicts
            ]

            print("📱 Starting audio recording with settings: \(settings)")

            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)

            // Check if recorder was created successfully
            guard let recorder = audioRecorder else {
                throw NSError(domain: "AudioRecording", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio recorder"])
            }

            // Prepare recorder and check for errors
            let prepareSuccess = recorder.prepareToRecord()
            print("📱 Audio recorder prepared: \(prepareSuccess)")

            if !prepareSuccess {
                throw NSError(domain: "AudioRecording", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare audio recorder"])
            }

            let success = recorder.record()
            print("📱 Audio recorder started: \(success)")

            if !success {
                // Get more details about why recording failed
                print("📱 Recorder URL: \(recorder.url)")
                print("📱 Recorder settings: \(recorder.settings)")
                print("📱 Audio session category: \(audioSession.category)")
                print("📱 Audio session mode: \(audioSession.mode)")

                throw NSError(domain: "AudioRecording", code: -3, userInfo: [NSLocalizedDescriptionKey: "Audio recorder.record() returned false - check device microphone access and audio session"])
            }

            withAnimation {
                isRecording = true
            }
        } catch {
            alertMessage = "Could not start recording: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func stopRecording() {
        print("📱 Stopping audio recording...")
        audioRecorder?.stop()

        // Wait a moment for recording to finalize, then check file
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Check recording result
            if let recordingURL = self.recordingURL {
                let fileExists = FileManager.default.fileExists(atPath: recordingURL.path)
                print("📱 Recording stopped, checking file at: \(recordingURL.path)")
                print("📱 File exists after recording stop: \(fileExists)")

                if fileExists {
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: recordingURL.path)
                        if let size = attributes[.size] as? NSNumber {
                            print("📱 File exists after recording stop. Size: \(size.intValue) bytes")
                        }
                    } catch {
                        print("⚠️ Error getting file attributes: \(error)")
                    }
                }
            }
        }

        // Clean up recorder
        audioRecorder = nil

        // Keep audio session active for potential playback
        // Don't deactivate immediately to avoid conflicts

        withAnimation {
            isRecording = false
        }
    }

    private func requestSpeechPermission() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                // Handle authorization status if needed
            }
        }
    }

    private func transcribeAudio(url: URL) {
        // Audio will be processed by backend during meal analysis
        // Don't add anything to the text field
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard let recordingURL = recordingURL else { return }

        // Check if running in simulator and file is too small
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif

        // Check file size before attempting playback
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: recordingURL.path)
            if let fileSize = attributes[.size] as? NSNumber {
                print("📱 Attempting playback of file size: \(fileSize.intValue) bytes")

                if fileSize.intValue < 1000 {
                    if isSimulator {
                        alertMessage = "Audio playback not available in simulator. Audio recording doesn't work properly in the iOS simulator - please test on a physical device for full audio functionality."
                        showingAlert = true
                        return
                    } else {
                        alertMessage = "Audio file too small to play (\(fileSize.intValue) bytes). Try recording for at least 3-5 seconds."
                        showingAlert = true
                        return
                    }
                }
            }
        } catch {
            print("⚠️ Error checking file attributes: \(error)")
        }

        do {
            // Set up audio session for playback
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: recordingURL)
            audioPlayer?.delegate = audioPlayerDelegate

            // Set up delegate callback
            audioPlayerDelegate.onFinish = {
                DispatchQueue.main.async {
                    withAnimation {
                        self.isPlaying = false
                    }
                    self.audioPlayer = nil
                }
            }

            audioPlayer?.play()

            withAnimation {
                isPlaying = true
            }
        } catch {
            alertMessage = "Could not play audio: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil

        withAnimation {
            isPlaying = false
        }
    }

    private func analyzeMeal() {
        isLoading = true
        Task {
            do {
                let parsed: MealParseDTO

                // Collect all available inputs
                let hasText = !mealText.isEmpty
                let hasImage = selectedImage != nil
                let hasAudio = recordingURL != nil

                // Step 1: Build combined description from text and audio
                var combinedDescription = ""

                // Add text if available
                if hasText {
                    combinedDescription = mealText.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                // Add audio transcription if available
                if hasAudio {
                    guard let audioURL = recordingURL else {
                        throw NSError(domain: "MealParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio recording found"])
                    }

                    // Verify audio file exists and is accessible
                    guard FileManager.default.fileExists(atPath: audioURL.path) else {
                        throw NSError(domain: "MealParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio file not found at path: \(audioURL.path)"])
                    }

                    // Read and validate audio data
                    let audioData: Data
                    do {
                        audioData = try Data(contentsOf: audioURL)
                        print("📱 Successfully read audio data: \(audioData.count) bytes")
                    } catch {
                        throw NSError(domain: "MealParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to read audio file: \(error.localizedDescription)"])
                    }

                    // Check if audio is valid (not empty M4A container)
                    #if targetEnvironment(simulator)
                    let isSimulator = true
                    #else
                    let isSimulator = false
                    #endif

                    if audioData.count < 1000 {
                        if isSimulator {
                            print("⚠️ Audio recording failed in simulator (only \(audioData.count) bytes). Skipping audio.")
                            // Skip audio in simulator, continue with text/image only
                        } else {
                            throw NSError(domain: "MealParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio file too small. Size: \(audioData.count) bytes. Try recording for at least 3-5 seconds."])
                        }
                    } else {
                        print("📱 Audio file validation passed: \(audioData.count) bytes")

                        // Use simple Whisper transcription as hints (no full meal parsing)
                        let audioTranscription = try await apiClient.transcribeAudio(audioData: audioData)

                        if !audioTranscription.isEmpty {
                            if !combinedDescription.isEmpty {
                                combinedDescription += ". "
                            }
                            // Add transcribed audio as hints for other parsing methods
                            combinedDescription += "Audio: \(audioTranscription)"
                        }
                    }
                }

                // Step 2: Choose parsing method based on available inputs
                if hasImage {
                    // Use image parsing with combined text+audio as hints
                    guard let image = selectedImage,
                          let imageData = image.jpegData(compressionQuality: 0.7) else {
                        throw NSError(domain: "MealParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
                    }

                    let base64String = imageData.base64EncodedString()
                    let imageUrl = "data:image/jpeg;base64,\(base64String)"

                    let hints = combinedDescription.isEmpty ? nil : combinedDescription
                    parsed = try await apiClient.parseMealImage(imageUrl: imageUrl, hints: hints)

                } else if !combinedDescription.isEmpty {
                    // Use combined text+audio description for text parsing
                    parsed = try await apiClient.parseMealText(text: combinedDescription)
                } else {
                    throw NSError(domain: "MealParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Please provide a meal description using text, photo, or audio."])
                }

                // Determine primary source for logging
                let primarySource: Meal.MealSource
                if hasImage {
                    primarySource = .image
                } else if hasAudio {
                    primarySource = .text  // Audio gets logged as text source for now
                } else {
                    primarySource = .text
                }

                let meal = Meal(
                    id: UUID(),
                    timestamp: Date(),
                    source: primarySource,
                    items: parsed.items,
                    totals: parsed.totals,
                    confidence: parsed.confidence,
                    notes: nil
                )

                // Log to backend
                _ = try await apiClient.logMeal(meal: meal, parse: parsed)

                // Refresh today's data
                await store.refreshTodayStats(apiClient: apiClient)

                await MainActor.run {
                    // Reset form
                    mealText = ""
                    selectedImage = nil
                    recordingURL = nil

                    alertMessage = "Meal logged successfully!\n\(parsed.totals.kcal) kcal\n" +
                                  "Protein: \(Int(parsed.totals.protein_g))g | " +
                                  "Carbs: \(Int(parsed.totals.carbs_g))g | " +
                                  "Fat: \(Int(parsed.totals.fat_g))g"
                    showingAlert = true
                    isLoading = false
                }

            } catch {
                await MainActor.run {
                    alertMessage = "Error analyzing meal: \(error.localizedDescription)"
                    showingAlert = true
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Unified Exercise Recording
struct UnifiedExerciseRecordView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @State private var exerciseDescription = ""
    @State private var exerciseType = ""
    @State private var duration = "30"
    @State private var intensity = 1 // 0: low, 1: moderate, 2: high
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var estimatedCalories: Int? = nil
    @State private var useNaturalLanguage = true
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var hasRecordingPermission = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var audioPlayerDelegate = AudioPlayerDelegate()
    @FocusState private var isTextEditorFocused: Bool

    private let intensityOptions = ["Low", "Moderate", "High"]
    private let intensityValues = ["low", "moderate", "high"]

    var body: some View {
        VStack(spacing: Theme.spacing.lg) {
            // Mode Toggle
            GlassCard {
                VStack(spacing: Theme.spacing.md) {
                    Text("Exercise Input Method")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    PillSegment(
                        items: ["Natural Language", "Manual Entry"],
                        selection: Binding(
                            get: { useNaturalLanguage ? 0 : 1 },
                            set: { useNaturalLanguage = ($0 == 0) }
                        )
                    )
                }
            }

            if useNaturalLanguage {
                // Natural Language Input
                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.spacing.md) {
                        Text("Describe your workout")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)

                        TextEditor(text: $exerciseDescription)
                            .frame(minHeight: 100)
                            .padding(12)
                            .scrollContentBackground(.hidden)
                            .background(Color.black.opacity(0.3))
                            .foregroundStyle(.white)
                            .tint(.white)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.sm, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.cornerRadius.sm, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .focused($isTextEditorFocused)
                            .keyboardToolbar {
                                isTextEditorFocused = false
                            }

                        Text("Example: \"Ran 3 miles in 30 minutes\" or \"Did strength training for 45 minutes\"")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                // Audio Input
                GlassCard {
                    VStack(spacing: Theme.spacing.md) {
                        Text("Or record your workout")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: Theme.spacing.md) {
                            Button(action: { toggleRecording() }) {
                                VStack(spacing: 8) {
                                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.fill")
                                        .font(.title)
                                        .foregroundStyle(isRecording ? Theme.danger : .white)
                                    Text(isRecording ? "Stop" : "Record")
                                        .font(.caption.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(isRecording ? Color.red.opacity(0.2) : Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.cornerRadius.md, style: .continuous)
                                        .stroke(isRecording ? Theme.danger.opacity(0.5) : Color.white.opacity(0.25), lineWidth: 1)
                                )
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }

                        if isRecording {
                            VStack(spacing: 4) {
                                HStack {
                                    Image(systemName: "waveform")
                                        .foregroundStyle(Theme.danger)
                                    Text("Recording... Describe your workout")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }

                                #if targetEnvironment(simulator)
                                Text("⚠️ Audio may not work in simulator")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.warn)
                                #endif
                            }
                            .padding(.top, 8)
                        }
                    }
                }

                // Audio Preview
                if recordingURL != nil {
                    GlassCard {
                        VStack(spacing: Theme.spacing.md) {
                            HStack {
                                Text("Workout Recording")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Button("Remove") {
                                    recordingURL = nil
                                }
                                .foregroundStyle(Theme.danger)
                            }

                            HStack(spacing: Theme.spacing.md) {
                                Image(systemName: "waveform")
                                    .font(.title)
                                    .foregroundStyle(Theme.accent)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Workout description recorded")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("Will be processed for exercise logging")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }

                                Spacer()

                                Button(action: { togglePlayback() }) {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(Theme.accent)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding()
                            .background(Color.black.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius.sm, style: .continuous))
                        }
                    }
                }

            } else {
                // Manual Entry (Original Form)
                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.spacing.lg) {
                        SectionHeader("Exercise Details")

                        // Exercise Type
                        VStack(alignment: .leading, spacing: Theme.spacing.sm) {
                            Text("Type")
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                            TextField("Running, Yoga, Weight training...", text: $exerciseType)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: exerciseType) { _ in
                                    estimatedCalories = nil
                                }
                        }

                        // Duration
                        HStack {
                            VStack(alignment: .leading, spacing: Theme.spacing.sm) {
                                Text("Duration")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                                HStack {
                                    TextField("30", text: $duration)
                                        .keyboardType(.numberPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                        .keyboardToolbar()
                                        .onChange(of: duration) { _ in
                                            estimatedCalories = nil
                                        }
                                    Text("minutes")
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            Spacer()
                        }

                        // Intensity
                        VStack(alignment: .leading, spacing: Theme.spacing.sm) {
                            Text("Intensity")
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                            PillSegment(items: intensityOptions, selection: $intensity)
                                .onChange(of: intensity) { _ in
                                    estimatedCalories = nil
                                }
                        }
                    }
                }
            }

            // Log Button
            PrimaryButton(
                title: "Analyze & Log Exercise",
                isLoading: isLoading
            ) {
                analyzeExercise()
            }
            .disabled((useNaturalLanguage && exerciseDescription.isEmpty && recordingURL == nil) ||
                     (!useNaturalLanguage && exerciseType.isEmpty))
        }
        .alert("Exercise Logging", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            requestMicrophonePermission()
        }
        .onDisappear {
            // Properly dismiss keyboard and clear focus to prevent session issues
            isTextEditorFocused = false
        }
        .tapToDismissKeyboard()
        .manageKeyboard()
    }

    private func requestMicrophonePermission() {
        let currentStatus = AVAudioSession.sharedInstance().recordPermission
        switch currentStatus {
        case .granted:
            hasRecordingPermission = true
        case .denied:
            hasRecordingPermission = false
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    self.hasRecordingPermission = granted
                }
            }
        @unknown default:
            hasRecordingPermission = false
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard hasRecordingPermission else {
            alertMessage = "Microphone permission is required for audio recording"
            showingAlert = true
            return
        }

        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try audioSession.setActive(true, options: [])

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioURL = documentsPath.appendingPathComponent("exercise_recording_\(Date().timeIntervalSince1970).m4a")
            recordingURL = audioURL

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1
            ]

            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            guard let recorder = audioRecorder else { return }

            let prepareSuccess = recorder.prepareToRecord()
            if !prepareSuccess {
                throw NSError(domain: "AudioRecording", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare audio recorder"])
            }

            let success = recorder.record()
            if !success {
                throw NSError(domain: "AudioRecording", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording"])
            }

            withAnimation {
                isRecording = true
            }
        } catch {
            alertMessage = "Could not start recording: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil

        withAnimation {
            isRecording = false
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard let recordingURL = recordingURL else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: recordingURL)
            audioPlayer?.delegate = audioPlayerDelegate

            audioPlayerDelegate.onFinish = {
                DispatchQueue.main.async {
                    withAnimation {
                        self.isPlaying = false
                    }
                    self.audioPlayer = nil
                }
            }

            audioPlayer?.play()

            withAnimation {
                isPlaying = true
            }
        } catch {
            alertMessage = "Could not play audio: \(error.localizedDescription)"
            showingAlert = true
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil

        withAnimation {
            isPlaying = false
        }
    }

    private func analyzeExercise() {
        isLoading = true
        Task {
            do {
                let parsed: ExerciseParseDTO

                if useNaturalLanguage {
                    // Collect all available inputs
                    let hasText = !exerciseDescription.isEmpty
                    let hasAudio = recordingURL != nil

                    var combinedDescription = ""

                    // Add text if available
                    if hasText {
                        combinedDescription = exerciseDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    // Add audio transcription if available
                    if hasAudio {
                        guard let audioURL = recordingURL else {
                            throw NSError(domain: "ExerciseParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio recording found"])
                        }

                        guard FileManager.default.fileExists(atPath: audioURL.path) else {
                            throw NSError(domain: "ExerciseParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio file not found"])
                        }

                        let audioData: Data
                        do {
                            audioData = try Data(contentsOf: audioURL)
                        } catch {
                            throw NSError(domain: "ExerciseParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to read audio file"])
                        }

                        #if targetEnvironment(simulator)
                        let isSimulator = true
                        #else
                        let isSimulator = false
                        #endif

                        if audioData.count < 1000 {
                            if isSimulator {
                                print("⚠️ Audio recording failed in simulator. Skipping audio.")
                            } else {
                                throw NSError(domain: "ExerciseParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio file too small"])
                            }
                        } else {
                            // Use simple Whisper transcription
                            let audioTranscription = try await apiClient.transcribeAudio(audioData: audioData)

                            if !audioTranscription.isEmpty {
                                if !combinedDescription.isEmpty {
                                    combinedDescription += ". "
                                }
                                combinedDescription += "Audio: \(audioTranscription)"
                            }
                        }
                    }

                    // Parse combined description
                    if !combinedDescription.isEmpty {
                        parsed = try await apiClient.parseExerciseText(text: combinedDescription)
                    } else {
                        throw NSError(domain: "ExerciseParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Please provide an exercise description using text or audio."])
                    }
                } else {
                    // Manual entry - use old method
                    guard !exerciseType.isEmpty,
                          let durationMin = Double(duration) else {
                        throw NSError(domain: "ExerciseParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Please provide exercise type and duration"])
                    }

                    let intensityValue = intensityValues[intensity]
                    let exercise = Exercise(
                        id: UUID(),
                        timestamp: Date(),
                        type: exerciseType,
                        duration_min: durationMin,
                        intensity: intensityValue,
                        est_kcal: estimatedCalories ?? Int(durationMin * 5)
                    )

                    // Log directly using old method
                    _ = try await apiClient.logExercise(exercise)

                    await store.refreshTodayStats(apiClient: apiClient)

                    await MainActor.run {
                        alertMessage = "Exercise logged!\n\(exerciseType) for \(Int(durationMin)) minutes\nBurned: \(exercise.est_kcal ?? 0) calories"
                        showingAlert = true

                        // Reset form
                        exerciseType = ""
                        duration = "30"
                        intensity = 1
                        estimatedCalories = nil
                        isLoading = false
                    }
                    return
                }

                // For natural language parsing, convert to Exercise and log
                guard let firstExercise = parsed.exercises.first else {
                    throw NSError(domain: "ExerciseParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "No exercises found in description"])
                }

                let exercise = Exercise(
                    id: UUID(),
                    timestamp: Date(),
                    type: parsed.exercises.count > 1 ?
                        parsed.exercises.map { $0.name }.joined(separator: ", ") :
                        firstExercise.name,
                    duration_min: firstExercise.duration_min ?? parsed.total_duration_min,
                    intensity: firstExercise.intensity,
                    est_kcal: firstExercise.est_kcal
                )

                // Log to backend
                _ = try await apiClient.logExercise(exercise)

                // Refresh today's data
                await store.refreshTodayStats(apiClient: apiClient)

                await MainActor.run {
                    // Reset form
                    exerciseDescription = ""
                    recordingURL = nil

                    let exerciseList = parsed.exercises.map { "\($0.name)" }.joined(separator: ", ")
                    alertMessage = "Exercise logged successfully!\n\(exerciseList)\nTotal: \(parsed.total_kcal) calories burned"
                    showingAlert = true
                    isLoading = false
                }

            } catch {
                await MainActor.run {
                    alertMessage = "Error analyzing exercise: \(error.localizedDescription)"
                    showingAlert = true
                    isLoading = false
                }
            }
        }
    }

}

// Separate component for WeightRecordView to maintain original structure
struct WeightRecordView: View {
    var body: some View {
        WeightRecordContent()
    }
}

struct WeightRecordContent: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @AppStorage("weight_unit") private var weightUnit = Config.defaultWeightUnit
    @State private var weight = ""
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: Theme.spacing.lg) {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.spacing.lg) {
                    HStack {
                        Image(systemName: "scalemass.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                        SectionHeader("Record Weight")
                        Spacer()

                        // Unit toggle
                        Picker("Unit", selection: $weightUnit) {
                            ForEach(Config.weightUnits, id: \.self) { unit in
                                Text(unit.uppercased()).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 90)
                    }

                    VStack(alignment: .leading, spacing: Theme.spacing.md) {
                        HStack {
                            TextField(WeightUtils.getPlaceholder(for: weightUnit), text: $weight)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                .keyboardToolbar()
                            Text(weightUnit)
                                .font(.headline)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                        }

                        Text("Range: \(WeightUtils.getWeightRange(for: weightUnit))")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            // Previous Weight
            if let latestWeight = store.latestWeight {
                GlassCard {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .foregroundStyle(Theme.textSecondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Previous Weight")
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                            Text(WeightUtils.displayWeight(latestWeight, unit: weightUnit))
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Spacer()
                        Text("Latest entry")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Log Button
            PrimaryButton(
                title: "Log Weight",
                isLoading: isLoading
            ) {
                logWeight()
            }
            .disabled(weight.isEmpty)
        }
        .alert("Weight Logging", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func logWeight() {
        guard let weightValue = Double(weight) else { return }

        // Validate weight in current unit
        guard WeightUtils.validateWeight(weightValue, unit: weightUnit) else {
            alertMessage = WeightUtils.getValidationError(for: weightUnit)
            showingAlert = true
            return
        }

        isLoading = true

        Task {
            do {
                // Convert to kg for backend storage
                let weightInKg = WeightUtils.convertToKg(weightValue, fromUnit: weightUnit)

                let weightEntry = Weight(
                    id: UUID(),
                    timestamp: Date(),
                    weight_kg: weightInKg,
                    method: "manual"
                )

                // Log to backend
                _ = try await apiClient.logWeight(weightEntry)

                // Refresh today's data
                await store.refreshTodayStats(apiClient: apiClient)

                await MainActor.run {
                    let displayWeight = WeightUtils.displayWeight(weightInKg, unit: weightUnit)
                    alertMessage = "Weight logged: \(displayWeight)"
                    showingAlert = true
                    weight = ""
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Error: \(error.localizedDescription)"
                    showingAlert = true
                    isLoading = false
                }
            }
        }
    }
}