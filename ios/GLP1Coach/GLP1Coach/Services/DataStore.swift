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

    // Task cancellation
    private var currentRefreshTask: Task<Void, Never>?
    private var currentSyncTask: Task<Void, Never>?
    
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
        // Cancel any existing refresh task
        currentRefreshTask?.cancel()

        currentRefreshTask = Task {
            guard !Task.isCancelled else { return }

            isLoading = true

            do {
                guard !Task.isCancelled else { return }
                todayStats = try await apiClient.getToday()
                errorMessage = nil
                offlineMode = false
                saveCachedData()
            } catch {
                guard !Task.isCancelled else { return }

                // Don't log cancellation as an error
                if (error as NSError).code == NSURLErrorCancelled {
                    return
                }

                print("⚠️ Failed to refresh today stats: \(error)")

                // Provide more specific error messages based on error type
                if let apiError = error as? APIError {
                    switch apiError {
                    case .unauthorized:
                        errorMessage = "Session expired. Please sign in again."
                        offlineMode = true
                    case .serverError(let code):
                        errorMessage = "Server temporarily unavailable (\(code))"
                        offlineMode = true
                    case .decodingError:
                        errorMessage = "Data format error. Using cached data."
                        offlineMode = false // This isn't necessarily an offline issue
                    }
                } else if (error as NSError).code == -1009 {
                    // Network offline error
                    errorMessage = "No internet connection. Using cached data."
                    offlineMode = true
                } else {
                    errorMessage = "Connection failed. Using cached data."
                    offlineMode = true
                }

                // Keep using cached data
            }

            guard !Task.isCancelled else { return }
            isLoading = false
        }

        await currentRefreshTask?.value
    }

    func clearCache() async {
        await MainActor.run {
            todayStats = nil
            weights.removeAll() // Clear local weight cache
            userDefaults.removeObject(forKey: todayStatsKey)
            userDefaults.removeObject(forKey: weightsKey)
            // Clear legacy weight unit key for clean sync
            userDefaults.removeObject(forKey: "weightUnit")
        }
    }

    func syncPendingData(apiClient: APIClient) async {
        guard pendingSyncCount > 0 else { return }

        // Cancel existing sync task
        currentSyncTask?.cancel()

        currentSyncTask = Task {
            guard !Task.isCancelled else { return }

            syncStatus = .syncing
            var syncErrors: [String] = []
        
            // Sync pending meals
            for i in 0..<meals.count {
                guard !Task.isCancelled else { return }

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
                    _ = try await apiClient.logMeal(meal: meals[i], parse: mealParse)
                    meals[i].syncStatus = .synced
                } catch {
                    meals[i].syncStatus = .failed
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .unauthorized:
                            syncErrors.append("Authentication required to sync meal")
                        case .serverError(let code):
                            syncErrors.append("Server error syncing meal (\(code))")
                        case .decodingError:
                            syncErrors.append("Data format error syncing meal")
                        }
                    } else {
                        syncErrors.append("Failed to sync meal: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Sync pending exercises
        for i in 0..<exercises.count {
            if exercises[i].syncStatus == .pending {
                exercises[i].syncStatus = .syncing
                do {
                    _ = try await apiClient.logExercise(exercises[i])
                    exercises[i].syncStatus = .synced
                } catch {
                    exercises[i].syncStatus = .failed
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .unauthorized:
                            syncErrors.append("Authentication required to sync exercise")
                        case .serverError(let code):
                            syncErrors.append("Server error syncing exercise (\(code))")
                        case .decodingError:
                            syncErrors.append("Data format error syncing exercise")
                        }
                    } else {
                        syncErrors.append("Failed to sync exercise: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Sync pending weights
        for i in 0..<weights.count {
            if weights[i].syncStatus == .pending {
                weights[i].syncStatus = .syncing
                do {
                    _ = try await apiClient.logWeight(weights[i])
                    weights[i].syncStatus = .synced
                } catch {
                    weights[i].syncStatus = .failed
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .unauthorized:
                            syncErrors.append("Authentication required to sync weight")
                        case .serverError(let code):
                            syncErrors.append("Server error syncing weight (\(code))")
                        case .decodingError:
                            syncErrors.append("Data format error syncing weight")
                        }
                    } else {
                        syncErrors.append("Failed to sync weight: \(error.localizedDescription)")
                    }
                }
            }
        }
        
            // Update sync status
            guard !Task.isCancelled else { return }

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

        await currentSyncTask?.value
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

    // MARK: - Enhanced Today Properties

    var calorieProgress: Double {
        todayStats?.calorie_progress ?? 0.0
    }

    var proteinProgress: Double {
        todayStats?.protein_progress ?? 0.0
    }

    var carbsProgress: Double {
        todayStats?.carbs_progress ?? 0.0
    }

    var fatProgress: Double {
        todayStats?.fat_progress ?? 0.0
    }

    var waterProgress: Double {
        todayStats?.water_progress ?? 0.0
    }

    var dailyTip: String? {
        todayStats?.daily_tip
    }

    var weeklyInsights: String? {
        // Generate AI insights based on recent data
        guard let stats = todayStats else { return nil }

        let weightUnit = UserDefaults.standard.string(forKey: "weight_unit") ?? Config.defaultWeightUnit
        let insights = generateWeeklyInsights(from: stats, weightUnit: weightUnit)
        return insights.isEmpty ? nil : insights
    }

    var streakDays: Int {
        todayStats?.streak_days ?? 0
    }

    var nextActions: [NextAction] {
        todayStats?.next_actions ?? []
    }

    var macroTargets: MacroTarget? {
        todayStats?.targets
    }

    var activitySummary: ActivitySummary? {
        todayStats?.activity
    }

    var sparklineData: DailySparkline? {
        todayStats?.sparkline
    }

    var weightTrend7d: Double? {
        todayStats?.weight_trend_7d
    }

    var medicationAdherence: Double {
        todayStats?.medication_adherence_pct ?? 100.0
    }

    var nextDoseTime: String? {
        todayStats?.next_dose_ts
    }

    var latestWeight: Double? {
        // Prioritize API data, fallback to local
        if let apiWeight = todayStats?.latest_weight_kg {
            return apiWeight
        }
        // Fallback to local weights array
        return weights.sorted(by: { $0.timestamp > $1.timestamp }).first?.weight_kg
    }

    // MARK: - Weight Display Helpers

    /// Get the latest weight formatted in the user's preferred unit
    /// - Parameter unit: Preferred weight unit ("kg" or "lbs")
    /// - Returns: Formatted weight string with unit, or nil if no weight data
    func getLatestWeightFormatted(unit: String) -> String? {
        guard let weightInKg = latestWeight else { return nil }
        return WeightUtils.displayWeight(weightInKg, unit: unit)
    }

    /// Get weight change since last entry
    /// - Parameter unit: Preferred weight unit for display
    /// - Returns: Weight change string with unit, or nil if insufficient data
    func getWeightChange(unit: String) -> String? {
        let sortedWeights = weights.sorted(by: { $0.timestamp > $1.timestamp })
        guard sortedWeights.count >= 2 else { return nil }

        let latest = sortedWeights[0].weight_kg
        let previous = sortedWeights[1].weight_kg
        let changeInKg = latest - previous

        let changeInUnit = WeightUtils.convertFromKg(abs(changeInKg), toUnit: unit)
        let sign = changeInKg >= 0 ? "+" : "-"

        return "\(sign)\(String(format: "%.1f", changeInUnit)) \(unit)"
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

    private func generateWeeklyInsights(from stats: TodayResp, weightUnit: String) -> String {
        var insights: [String] = []

        // Weight trend insights
        if let weightTrend = stats.weight_trend_7d {
            let convertedTrend = WeightUtils.convertFromKg(abs(weightTrend), toUnit: weightUnit)
            if weightTrend < -0.5 {
                insights.append("🎉 Great progress! You've lost \(String(format: "%.1f", convertedTrend)) \(weightUnit) this week.")
            } else if weightTrend > 0.5 {
                insights.append("📈 Weight increased by \(String(format: "%.1f", convertedTrend)) \(weightUnit) this week. Consider reviewing your nutrition goals.")
            } else {
                insights.append("⚖️ Weight staying stable this week - consistency is key!")
            }
        }

        // Calorie adherence insights
        let calorieAdherence = stats.calorie_progress
        if calorieAdherence < 0.7 {
            insights.append("Consider adding more balanced meals to reach your calorie goals.")
        } else if calorieAdherence > 1.2 {
            insights.append("You're exceeding your calorie target. Try focusing on portion control.")
        }

        // Protein insights
        let proteinProgress = stats.protein_progress
        if proteinProgress < 0.8 {
            insights.append("Add more protein-rich foods like chicken, fish, or legumes to your meals.")
        }

        // Activity insights
        let mealsLogged = stats.activity.meals_logged
        let exercisesLogged = stats.activity.exercises_logged
        if mealsLogged >= 3 && exercisesLogged > 0 {
            insights.append("Excellent logging consistency! Keep tracking both nutrition and exercise.")
        } else if mealsLogged < 2 {
            insights.append("Try logging all your meals for better insights into your progress.")
        }

        // Return the first 2 most relevant insights
        return insights.prefix(2).joined(separator: " ")
    }
}