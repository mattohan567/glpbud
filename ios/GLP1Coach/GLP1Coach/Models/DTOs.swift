import Foundation

// MARK: - API Response DTOs

struct MacroTotals: Codable {
    let kcal: Int
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
}

struct MealItemDTO: Codable {
    let name: String
    let qty: Double
    let unit: String
    let kcal: Int
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
    let fdc_id: Int?
}

struct MealParseDTO: Codable {
    let items: [MealItemDTO]
    let totals: MacroTotals
    let confidence: Double
    let questions: [String]?
    let low_confidence: Bool
}

struct ExerciseItemDTO: Codable {
    let name: String
    let category: String
    let duration_min: Double?
    let sets: Int?
    let reps: Int?
    let weight_kg: Double?
    let intensity: String
    let equipment: String?
    let est_kcal: Int
}

struct ExerciseParseDTO: Codable {
    let exercises: [ExerciseItemDTO]
    let total_duration_min: Double
    let total_kcal: Int
    let confidence: Double
    let questions: [String]?
    let low_confidence: Bool
}

struct IdResp: Codable {
    let ok: Bool
    let id: String
}

// MARK: - Enhanced Today Response Models

struct DailySparkline: Codable {
    let dates: [String]  // ISO date strings
    let calories: [Int]  // Net calories per day
    let weights: [Double?]  // May have null values for missing days
}

struct MacroTarget: Codable {
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
    let calories: Int
}

struct ActivitySummary: Codable {
    let meals_logged: Int
    let exercises_logged: Int
    let water_ml: Int
    let steps: Int?
}

struct NextAction: Codable {
    let type: String  // "log_meal", "log_exercise", "log_weight", etc.
    let title: String
    let subtitle: String?
    let time_due: String?  // ISO timestamp
    let icon: String  // SF Symbol name
}

struct TodayResp: Codable {
    let date: String

    // Current totals
    let kcal_in: Int
    let kcal_out: Int
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
    let water_ml: Int

    // Personalized targets
    let targets: MacroTarget

    // Progress percentages (0-1.0)
    let calorie_progress: Double
    let protein_progress: Double
    let carbs_progress: Double
    let fat_progress: Double
    let water_progress: Double

    // Activity summary
    let activity: ActivitySummary

    // Medication tracking
    let next_dose_ts: String?
    let medication_adherence_pct: Double

    // Recent activity timeline - simplified as strings for now
    let last_logs: [String]
    let todays_meals: [String]
    let todays_exercises: [String]

    // 7-day sparkline data
    let sparkline: DailySparkline

    // Weight tracking
    let latest_weight_kg: Double?
    let weight_trend_7d: Double?

    // Smart insights
    let daily_tip: String?
    let streak_days: Int

    // Suggested next actions
    let next_actions: [NextAction]

    // Custom decoder to handle complex JSON arrays gracefully
    enum CodingKeys: String, CodingKey {
        case date, kcal_in, kcal_out, protein_g, carbs_g, fat_g, water_ml
        case targets, calorie_progress, protein_progress, carbs_progress, fat_progress, water_progress
        case activity, next_dose_ts, medication_adherence_pct
        case last_logs, todays_meals, todays_exercises
        case sparkline, latest_weight_kg, weight_trend_7d
        case daily_tip, streak_days, next_actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        date = try container.decode(String.self, forKey: .date)
        kcal_in = try container.decode(Int.self, forKey: .kcal_in)
        kcal_out = try container.decode(Int.self, forKey: .kcal_out)
        protein_g = try container.decode(Double.self, forKey: .protein_g)
        carbs_g = try container.decode(Double.self, forKey: .carbs_g)
        fat_g = try container.decode(Double.self, forKey: .fat_g)
        water_ml = try container.decode(Int.self, forKey: .water_ml)

        targets = try container.decode(MacroTarget.self, forKey: .targets)
        calorie_progress = try container.decode(Double.self, forKey: .calorie_progress)
        protein_progress = try container.decode(Double.self, forKey: .protein_progress)
        carbs_progress = try container.decode(Double.self, forKey: .carbs_progress)
        fat_progress = try container.decode(Double.self, forKey: .fat_progress)
        water_progress = try container.decode(Double.self, forKey: .water_progress)

        activity = try container.decode(ActivitySummary.self, forKey: .activity)
        next_dose_ts = try container.decodeIfPresent(String.self, forKey: .next_dose_ts)
        medication_adherence_pct = try container.decode(Double.self, forKey: .medication_adherence_pct)

        sparkline = try container.decode(DailySparkline.self, forKey: .sparkline)
        latest_weight_kg = try container.decodeIfPresent(Double.self, forKey: .latest_weight_kg)
        weight_trend_7d = try container.decodeIfPresent(Double.self, forKey: .weight_trend_7d)

        daily_tip = try container.decodeIfPresent(String.self, forKey: .daily_tip)
        streak_days = try container.decode(Int.self, forKey: .streak_days)
        next_actions = try container.decode([NextAction].self, forKey: .next_actions)

        // Handle complex arrays gracefully - decode as empty for now
        // The enhanced TodayView will use simpler summary data instead
        last_logs = []
        todays_meals = []
        todays_exercises = []
    }
}

struct NextDoseResp: Codable {
    let next_dose_ts: String?
}

struct CoachResp: Codable {
    let answer: String
    let disclaimers: [String]
    let references: [String]
}

// MARK: - Local Models

struct Meal: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let source: MealSource
    let items: [MealItemDTO]
    let totals: MacroTotals
    let confidence: Double
    let notes: String?
    var syncStatus: SyncStatus = .pending
    
    enum MealSource: String, Codable {
        case image, text, manual
    }
}

struct Exercise: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let type: String
    let duration_min: Double
    let intensity: String?
    let est_kcal: Int?
    var syncStatus: SyncStatus = .pending
}

struct Weight: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let weight_kg: Double
    let method: String
    var syncStatus: SyncStatus = .pending
}

struct Medication: Identifiable, Codable {
    let id: UUID
    let drug_name: String
    let dose_mg: Double
    let schedule_rule: String
    let start_ts: Date
    let notes: String?
    let active: Bool
}

enum SyncStatus: String, Codable {
    case pending, syncing, synced, failed
}

// MARK: - History Models

struct HistoryEntryResp: Identifiable, Decodable {
    let id: String
    let ts: Date
    let type: EntryType
    let display_name: String
    let details: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case id, ts, type, display_name, details
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        
        // Decode the timestamp string and convert to Date
        let tsString = try container.decode(String.self, forKey: .ts)
        
        // Try multiple ISO8601 formatters to handle different timestamp formats
        let standardFormatter = ISO8601DateFormatter()
        
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let internetFormatter = ISO8601DateFormatter()
        internetFormatter.formatOptions = [.withInternetDateTime]
        
        let formatters = [standardFormatter, fractionalFormatter, internetFormatter]
        
        var parsedDate: Date?
        for formatter in formatters {
            if let date = formatter.date(from: tsString) {
                parsedDate = date
                break
            }
        }
        
        if let date = parsedDate {
            ts = date
        } else {
            // Log the parsing failure for debugging
            print("⚠️ Failed to parse timestamp: '\(tsString)' for entry ID: \(id)")
            // Keep the current fallback but make it explicit
            ts = Date()
        }
        
        type = try container.decode(EntryType.self, forKey: .type)
        display_name = try container.decode(String.self, forKey: .display_name)
        
        // Decode details as a generic dictionary
        if let detailsDict = try? container.decode([String: AnyCodable].self, forKey: .details) {
            details = detailsDict.mapValues { $0.value }
        } else {
            details = [:]
        }
    }
    
    enum EntryType: String, Codable, CaseIterable {
        case meal, exercise, weight, medication
        
        var displayName: String {
            switch self {
            case .meal: return "Meal"
            case .exercise: return "Exercise"
            case .weight: return "Weight"
            case .medication: return "Medication"
            }
        }
        
        var icon: String {
            switch self {
            case .meal: return "fork.knife"
            case .exercise: return "figure.walk"
            case .weight: return "scalemass"
            case .medication: return "pills"
            }
        }
    }
}

struct HistoryResp: Decodable {
    let entries: [HistoryEntryResp]
    let total_count: Int
}

struct UpdateMealReq: Codable {
    let items: [MealItemDTO]
    let notes: String?
}

struct UpdateExerciseReq: Codable {
    let type: String
    let duration_min: Double
    let intensity: String?
    let est_kcal: Int?
}

struct UpdateWeightReq: Codable {
    let weight_kg: Double
    let method: String
}

// MARK: - Trends and Streaks Models

struct WeightPoint: Codable {
    let date: Date
    let weight_kg: Double
}

struct CaloriePoint: Codable {
    let date: Date
    let intake: Int
    let burned: Int
    let net: Int
}

struct StreakInfo: Codable {
    let type: String
    let current_streak: Int
    let longest_streak: Int
    let last_activity: Date?

    var displayName: String {
        switch type {
        case "logging": return "Daily Logging"
        case "meals": return "Meal Tracking"
        case "exercise": return "Exercise"
        case "weight": return "Weight Tracking"
        default: return type.capitalized
        }
    }

    var icon: String {
        switch type {
        case "logging": return "calendar"
        case "meals": return "fork.knife"
        case "exercise": return "figure.walk"
        case "weight": return "scalemass"
        default: return "star"
        }
    }
}

struct Achievement: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let earned_at: Date?
    let progress: Double
}

struct TrendsResp: Codable {
    let weight_trend: [WeightPoint]
    let calorie_trend: [CaloriePoint]
    let current_streaks: [StreakInfo]
    let achievements: [Achievement]
    let insights: [String]
}

// Helper for dynamic JSON decoding
struct AnyCodable: Codable {
    let value: Any
    
    init<T>(_ value: T?) {
        self.value = value ?? ()
    }
}

extension AnyCodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictionaryValue = try? container.decode([String: AnyCodable].self) {
            value = dictionaryValue.mapValues { $0.value }
        } else {
            value = ()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            let codableArray = arrayValue.map { AnyCodable($0) }
            try container.encode(codableArray)
        case let dictionaryValue as [String: Any]:
            let codableDictionary = dictionaryValue.mapValues { AnyCodable($0) }
            try container.encode(codableDictionary)
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Chat Models

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let disclaimers: [String]
    let actions: [LoggedActionResp]
    let timestamp = Date()
    
    enum Role {
        case user, coach
    }
    
    init(role: Role, content: String, disclaimers: [String] = [], actions: [LoggedActionResp] = []) {
        self.role = role
        self.content = content
        self.disclaimers = disclaimers
        self.actions = actions
    }
}

// MARK: - Agentic Coach Models

struct CoachChatReq: Codable {
    let message: String
    let context_opt_in: Bool
}

struct LoggedActionResp: Codable, Identifiable {
    let id: String
    let type: String
    let summary: String
    let details: [String: AnyCodable]
}

struct AgenticCoachResp: Codable {
    let message: String
    let actions_taken: [LoggedActionResp]
    let disclaimers: [String]
}
