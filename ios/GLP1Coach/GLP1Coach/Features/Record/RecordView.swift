import SwiftUI
import PhotosUI

struct RecordView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("Record Type", selection: $selectedTab) {
                    Text("Meal").tag(0)
                    Text("Exercise").tag(1)
                    Text("Weight").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                TabView(selection: $selectedTab) {
                    MealRecordView().tag(0)
                    ExerciseRecordView().tag(1)
                    WeightRecordView().tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Record")
        }
    }
}

struct MealRecordView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @State private var mealText = ""
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var showingCamera = false
    @State private var inputMode = 0 // 0: text, 1: photo
    
    var body: some View {
        VStack(spacing: 20) {
            // Input mode selector
            Picker("Input Mode", selection: $inputMode) {
                Label("Text", systemImage: "text.cursor").tag(0)
                Label("Photo", systemImage: "camera").tag(1)
            }
            .pickerStyle(.segmented)
            
            if inputMode == 0 {
                // Text input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe your meal")
                        .font(.headline)
                    
                    TextEditor(text: $mealText)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    
                    Text("Example: Grilled chicken breast 200g with rice")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // Photo input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Take or select a photo")
                        .font(.headline)
                    
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                            .onTapGesture {
                                showingImagePicker = true
                            }
                    } else {
                        HStack(spacing: 20) {
                            Button(action: { showingCamera = true }) {
                                VStack {
                                    Image(systemName: "camera.fill")
                                        .font(.largeTitle)
                                    Text("Camera")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                            
                            Button(action: { showingImagePicker = true }) {
                                VStack {
                                    Image(systemName: "photo.fill")
                                        .font(.largeTitle)
                                    Text("Library")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    Text("AI will analyze the photo for nutritional info")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button(action: parseMeal) {
                if isLoading {
                    ProgressView()
                } else {
                    Label("Analyze & Log", systemImage: inputMode == 0 ? "text.magnifyingglass" : "photo.badge.checkmark")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled((inputMode == 0 && mealText.isEmpty) || (inputMode == 1 && selectedImage == nil) || isLoading)
            
            Spacer()
        }
        .padding()
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
    }
    
    private func parseMeal() {
        isLoading = true
        Task {
            do {
                let parsed: MealParseDTO
                
                if inputMode == 0 {
                    // Text parsing
                    parsed = try await apiClient.parseMealText(text: mealText)
                } else {
                    // Image parsing
                    guard let image = selectedImage,
                          let imageData = image.jpegData(compressionQuality: 0.7) else {
                        throw NSError(domain: "MealParsing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
                    }
                    
                    let base64String = imageData.base64EncodedString()
                    let imageUrl = "data:image/jpeg;base64,\(base64String)"
                    parsed = try await apiClient.parseMealImage(imageUrl: imageUrl)
                }
                
                let meal = Meal(
                    id: UUID(),
                    timestamp: Date(),
                    source: inputMode == 0 ? .text : .image,
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
                    mealText = ""
                    selectedImage = nil
                    alertMessage = "Meal logged: \(parsed.totals.kcal) kcal\n" +
                                  "Protein: \(Int(parsed.totals.protein_g))g | " +
                                  "Carbs: \(Int(parsed.totals.carbs_g))g | " +
                                  "Fat: \(Int(parsed.totals.fat_g))g"
                    showingAlert = true
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

struct ExerciseRecordView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @State private var exerciseType = ""
    @State private var duration = "30"
    @State private var intensity = "moderate"
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var estimatedCalories: Int? = nil
    
    var body: some View {
        Form {
            Section("Exercise Details") {
                TextField("Type (e.g., Running, Yoga, Weight training)", text: $exerciseType)
                    .onChange(of: exerciseType) { _ in
                        estimatedCalories = nil
                    }
                
                HStack {
                    Text("Duration")
                    TextField("Minutes", text: $duration)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: duration) { _ in
                            estimatedCalories = nil
                        }
                    Text("min")
                }
                
                Picker("Intensity", selection: $intensity) {
                    Text("Low").tag("low")
                    Text("Moderate").tag("moderate")
                    Text("High").tag("high")
                }
                .onChange(of: intensity) { _ in
                    estimatedCalories = nil
                }
            }
            
            if let calories = estimatedCalories {
                Section("Estimated Burn") {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                        Text("\(calories) calories")
                            .font(.headline)
                    }
                }
            }
            
            Section {
                Button(action: logExercise) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Log Exercise")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(exerciseType.isEmpty || duration.isEmpty || isLoading)
            }
        }
        .alert("Exercise Logging", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func logExercise() {
        guard !exerciseType.isEmpty,
              let durationMin = Double(duration) else { return }
        
        isLoading = true
        
        Task {
            do {
                // Create exercise with Claude-estimated calories
                let exercise = Exercise(
                    id: UUID(),
                    timestamp: Date(),
                    type: exerciseType,
                    duration_min: durationMin,
                    intensity: intensity,
                    est_kcal: estimatedCalories ?? Int(durationMin * 5)
                )
                
                // Log to backend
                _ = try await apiClient.logExercise(exercise)
                
                // Refresh today's data
                await store.refreshTodayStats(apiClient: apiClient)
                
                await MainActor.run {
                    // Show success with calorie info
                    alertMessage = "Exercise logged!\n\(exerciseType) for \(Int(durationMin)) minutes\nBurned: \(exercise.est_kcal ?? 0) calories"
                    showingAlert = true
                    
                    // Reset form
                    exerciseType = ""
                    duration = "30"
                    intensity = "moderate"
                    estimatedCalories = nil
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

struct WeightRecordView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var apiClient: APIClient
    @State private var weight = ""
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        Form {
            Section("Weight") {
                HStack {
                    TextField("Weight", text: $weight)
                        .keyboardType(.decimalPad)
                    Text("kg")
                }
            }
            
            Section {
                Button(action: logWeight) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Log Weight")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(weight.isEmpty || isLoading)
            }
            
            if let latestWeight = store.latestWeight {
                Section("Previous") {
                    HStack {
                        Text(String(format: "%.1f kg", latestWeight))
                        Spacer()
                        Text("From latest data")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .alert("Weight Logging", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func logWeight() {
        guard let weightValue = Double(weight) else { return }
        
        isLoading = true
        
        Task {
            do {
                let weightEntry = Weight(
                    id: UUID(),
                    timestamp: Date(),
                    weight_kg: weightValue,
                    method: "manual"
                )
                
                // Log to backend
                _ = try await apiClient.logWeight(weightEntry)
                
                // Refresh today's data  
                await store.refreshTodayStats(apiClient: apiClient)
                
                await MainActor.run {
                    alertMessage = "Weight logged: \(String(format: "%.1f", weightValue)) kg"
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