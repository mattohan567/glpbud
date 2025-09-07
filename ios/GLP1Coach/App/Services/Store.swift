import Foundation
import CoreData
import Combine

@MainActor
final class DataStore: ObservableObject {
    @Published var meals: [Meal] = []
    @Published var exercises: [Exercise] = []
    @Published var weights: [Weight] = []
    @Published var medications: [Medication] = []
    @Published var todayStats: TodayResp?
    
    private let userDefaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init() {
        loadCachedData()
    }
    
    // MARK: - Persistence
    
    func loadCachedData() {
        if let data = userDefaults.data(forKey: "cached_meals"),
           let decoded = try? decoder.decode([Meal].self, from: data) {
            self.meals = decoded
        }
        
        if let data = userDefaults.data(forKey: "cached_exercises"),
           let decoded = try? decoder.decode([Exercise].self, from: data) {
            self.exercises = decoded
        }
        
        if let data = userDefaults.data(forKey: "cached_weights"),
           let decoded = try? decoder.decode([Weight].self, from: data) {
            self.weights = decoded
        }
        
        if let data = userDefaults.data(forKey: "cached_today"),
           let decoded = try? decoder.decode(TodayResp.self, from: data) {
            self.todayStats = decoded
        }
    }
    
    func saveCachedData() {
        if let encoded = try? encoder.encode(meals) {
            userDefaults.set(encoded, forKey: "cached_meals")
        }
        
        if let encoded = try? encoder.encode(exercises) {
            userDefaults.set(encoded, forKey: "cached_exercises")
        }
        
        if let encoded = try? encoder.encode(weights) {
            userDefaults.set(encoded, forKey: "cached_weights")
        }
        
        if let encoded = try? encoder.encode(todayStats) {
            userDefaults.set(encoded, forKey: "cached_today")
        }
    }
    
    // MARK: - Local Operations (Optimistic UI)
    
    func addMeal(_ meal: Meal) {
        meals.append(meal)
        meals.sort { $0.timestamp > $1.timestamp }
        saveCachedData()
    }
    
    func addExercise(_ exercise: Exercise) {
        exercises.append(exercise)
        exercises.sort { $0.timestamp > $1.timestamp }
        saveCachedData()
    }
    
    func addWeight(_ weight: Weight) {
        weights.append(weight)
        weights.sort { $0.timestamp > $1.timestamp }
        saveCachedData()
    }
    
    func updateSyncStatus<T: Identifiable>(for item: T, status: SyncStatus) where T: AnyObject {
        if let meal = item as? Meal,
           let index = meals.firstIndex(where: { $0.id == meal.id }) {
            meals[index].syncStatus = status
        } else if let exercise = item as? Exercise,
                  let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
            exercises[index].syncStatus = status
        } else if let weight = item as? Weight,
                  let index = weights.firstIndex(where: { $0.id == weight.id }) {
            weights[index].syncStatus = status
        }
        saveCachedData()
    }
    
    // MARK: - Computed Properties
    
    var todayMeals: [Meal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return meals.filter { calendar.isDate($0.timestamp, inSameDayAs: today) }
    }
    
    var todayExercises: [Exercise] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return exercises.filter { calendar.isDate($0.timestamp, inSameDayAs: today) }
    }
    
    var todayCaloriesIn: Int {
        todayMeals.reduce(0) { $0 + $1.totals.kcal }
    }
    
    var todayCaloriesOut: Int {
        todayExercises.reduce(0) { $0 + ($1.est_kcal ?? 0) }
    }
    
    var todayProtein: Double {
        todayMeals.reduce(0) { $0 + $1.totals.protein_g }
    }
    
    var latestWeight: Weight? {
        weights.first
    }
    
    // MARK: - Sync Management
    
    func syncPendingItems() async {
        // This would be called by background task or manual refresh
        let pendingMeals = meals.filter { $0.syncStatus == .pending }
        let pendingExercises = exercises.filter { $0.syncStatus == .pending }
        let pendingWeights = weights.filter { $0.syncStatus == .pending }
        
        // Sync logic would go here, calling APIClient methods
        // and updating sync status accordingly
    }
}