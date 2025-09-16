import Foundation
import Combine

@MainActor
final class DataStore: ObservableObject {
    // Published properties for UI binding with offline support
    @Published var todayStats: TodayResp?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var syncStatus: SyncStatus = .synced
    @Published var offlineMode = false
    
    // Local storage with sync status
    @Published var meals: [Meal] = []
    @Published var exercises: [Exercise] = []
    @Published var weights: [Weight] = []
    
    // Sync tracking
    @Published var pendingSyncCount = 0
    
    private let userDefaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // Keys for UserDefaults caching
    private let mealsKey = "cached_meals"
    private let exercisesKey = "cached_exercises"
    private let weightsKey = "cached_weights"
    private let todayStatsKey = "cached_today_stats"
    private let lastSyncKey = "last_sync_timestamp"
    
    init() {
        setupDateFormatting()
        loadCachedData()
        startSyncStatusMonitoring()
    }
    
    private func setupDateFormatting() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    private func startSyncStatusMonitoring() {
        // Monitor for changes in data arrays to update sync status
        $meals
            .combineLatest($exercises, $weights)
            .map { meals, exercises, weights in
                meals.filter { $0.syncStatus != .synced }.count +
                exercises.filter { $0.syncStatus != .synced }.count +
                weights.filter { $0.syncStatus != .synced }.count
            }
            .assign(to: &$pendingSyncCount)
    }
    
    // MARK: - Data Loading and Caching
    
    private func loadCachedData() {
        // Load cached meals
        if let mealsData = userDefaults.data(forKey: mealsKey),
           let cachedMeals = try? decoder.decode([Meal].self, from: mealsData) {
            self.meals = cachedMeals
        }
        
        // Load cached exercises
        if let exercisesData = userDefaults.data(forKey: exercisesKey),
           let cachedExercises = try? decoder.decode([Exercise].self, from: exercisesData) {
            self.exercises = cachedExercises
        }
        
        // Load cached weights
        if let weightsData = userDefaults.data(forKey: weightsKey),
           let cachedWeights = try? decoder.decode([Weight].self, from: weightsData) {
            self.weights = cachedWeights
        }
        
        // Load cached today stats
        if let todayData = userDefaults.data(forKey: todayStatsKey),
           let cachedToday = try? decoder.decode(TodayResp.self, from: todayData) {
            self.todayStats = cachedToday
        }
    }
    
    private func saveCachedData() {
        // Save meals
        if let mealsData = try? encoder.encode(meals) {
            userDefaults.set(mealsData, forKey: mealsKey)
        }
        
        // Save exercises
        if let exercisesData = try? encoder.encode(exercises) {
            userDefaults.set(exercisesData, forKey: exercisesKey)
        }
        
        // Save weights
        if let weightsData = try? encoder.encode(weights) {
            userDefaults.set(weightsData, forKey: weightsKey)
        }
        
        // Save today stats
        if let todayData = try? encoder.encode(todayStats) {
            userDefaults.set(todayData, forKey: todayStatsKey)
        }
        
        // Update last sync timestamp
        userDefaults.set(Date(), forKey: lastSyncKey)
    }
    
    // MARK: - Clear All Data (for logout)
    
    func clearAllData() {
        meals.removeAll()
        exercises.removeAll()
        weights.removeAll()
        todayStats = nil
        errorMessage = nil
        isLoading = false
        syncStatus = .synced
        offlineMode = false
        pendingSyncCount = 0
        
        // Clear cached data
        userDefaults.removeObject(forKey: mealsKey)
        userDefaults.removeObject(forKey: exercisesKey)
        userDefaults.removeObject(forKey: weightsKey)
        userDefaults.removeObject(forKey: todayStatsKey)
        userDefaults.removeObject(forKey: lastSyncKey)
    }
    
    // MARK: - Data Synchronization
    
    func refreshTodayStats(apiClient: APIClient) async {
        isLoading = true
        do {
            todayStats = try await apiClient.getToday()
            errorMessage = nil
            offlineMode = false
            saveCachedData()
        } catch {
            errorMessage = "Failed to refresh data: \(error.localizedDescription)"
            offlineMode = true
            // Keep using cached data
        }
        isLoading = false
    }
    
    func syncPendingData(apiClient: APIClient) async {
        guard pendingSyncCount > 0 else { return }
        
        syncStatus = .syncing
        var syncErrors: [String] = []
        
        // Sync pending meals
        for i in 0..<meals.count {
            if meals[i].syncStatus == .pending {
                meals[i].syncStatus = .syncing
                do {
                    let mealParse = MealParseDTO(
                        items: meals[i].items,
                        totals: meals[i].totals,
                        confidence: meals[i].confidence,
                        questions: nil,
                        low_confidence: meals[i].confidence < 0.6
                    )
                    let result = try await apiClient.logMeal(meal: meals[i], parse: mealParse)
                    meals[i].syncStatus = .synced
                } catch {
                    meals[i].syncStatus = .failed
                    syncErrors.append("Failed to sync meal: \(error.localizedDescription)")
                }
            }
        }
        
        // Sync pending exercises
        for i in 0..<exercises.count {
            if exercises[i].syncStatus == .pending {
                exercises[i].syncStatus = .syncing
                do {
                    let result = try await apiClient.logExercise(exercises[i])
                    exercises[i].syncStatus = .synced
                } catch {
                    exercises[i].syncStatus = .failed
                    syncErrors.append("Failed to sync exercise: \(error.localizedDescription)")
                }
            }
        }
        
        // Sync pending weights
        for i in 0..<weights.count {
            if weights[i].syncStatus == .pending {
                weights[i].syncStatus = .syncing
                do {
                    let result = try await apiClient.logWeight(weights[i])
                    weights[i].syncStatus = .synced
                } catch {
                    weights[i].syncStatus = .failed
                    syncErrors.append("Failed to sync weight: \(error.localizedDescription)")
                }
            }
        }
        
        // Update sync status
        if syncErrors.isEmpty {
            syncStatus = .synced
            offlineMode = false
        } else {
            syncStatus = .failed
            errorMessage = syncErrors.joined(separator: "\n")
        }
        
        // Save updated data
        saveCachedData()
    }
    
    // MARK: - Data Management
    
    func addMeal(_ meal: Meal) {
        var mutableMeal = meal
        mutableMeal.syncStatus = .pending
        meals.append(mutableMeal)
        saveCachedData()
        
        // Try to sync immediately if online
        if !offlineMode {
            Task {
                await syncPendingData(with: APIClient())
            }
        }
    }
    
    func addExercise(_ exercise: Exercise) {
        var mutableExercise = exercise
        mutableExercise.syncStatus = .pending
        exercises.append(mutableExercise)
        saveCachedData()
        
        // Try to sync immediately if online
        if !offlineMode {
            Task {
                await syncPendingData(with: APIClient())
            }
        }
    }
    
    func addWeight(_ weight: Weight) {
        var mutableWeight = weight
        mutableWeight.syncStatus = .pending
        weights.append(mutableWeight)
        saveCachedData()
        
        // Try to sync immediately if online
        if !offlineMode {
            Task {
                await syncPendingData(with: APIClient())
            }
        }
    }
    
    // Helper function for syncing with provided API client
    private func syncPendingData(with apiClient: APIClient) async {
        await syncPendingData(apiClient: apiClient)
    }
    
    func updateSyncStatus(for itemId: UUID, status: SyncStatus, in collection: ItemType) {
        switch collection {
        case .meal:
            if let index = meals.firstIndex(where: { $0.id == itemId }) {
                meals[index].syncStatus = status
            }
        case .exercise:
            if let index = exercises.firstIndex(where: { $0.id == itemId }) {
                exercises[index].syncStatus = status
            }
        case .weight:
            if let index = weights.firstIndex(where: { $0.id == itemId }) {
                weights[index].syncStatus = status
            }
        }
        saveCachedData()
    }
    
    enum ItemType {
        case meal, exercise, weight
    }
    
    // MARK: - Computed Properties (from API data)
    
    var todayCaloriesIn: Int {
        todayStats?.kcal_in ?? 0
    }
    
    var todayCaloriesOut: Int {
        todayStats?.kcal_out ?? 0
    }
    
    var todayProtein: Double {
        todayStats?.protein_g ?? 0
    }
    
    var todayCarbs: Double {
        todayStats?.carbs_g ?? 0
    }
    
    var todayFat: Double {
        todayStats?.fat_g ?? 0
    }
    
    var latestWeight: Double? {
        // TodayResp doesn't include weight data yet
        // This will be nil until we add weight to the API response
        return nil
    }
    
    var todayMeals: [Meal] {
        // Return empty array for now - will be fetched from API
        // This is here for backward compatibility
        []
    }
    
    var todayExercises: [Exercise] {
        // Return empty array for now - will be fetched from API
        // This is here for backward compatibility
        []
    }
    
    // MARK: - Removed Methods
    // The following methods are removed as we no longer cache locally:
    // - loadCachedData()
    // - saveCachedData()
    // - addMeal()
    // - addExercise()
    // - addWeight()
    // - updateSyncStatus()
    
    // These operations should now be done directly through APIClient
}