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

struct IdResp: Codable {
    let ok: Bool
    let id: String
}

struct TodayResp: Codable {
    let date: String
    let kcal_in: Int
    let kcal_out: Int
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
    let next_dose_ts: String?
    let last_logs: [[String: String]]
}

struct WeightDataPoint: Codable {
    let ts: String
    let kg: Double
}

struct MacroDataPoint: Codable {
    let date: String
    let kcal: Int
}

struct ProteinDataPoint: Codable {
    let date: String
    let g: Double
}

struct TrendsResp: Codable {
    let range: String
    let weight_series: [WeightDataPoint]
    let kcal_in_series: [MacroDataPoint]
    let kcal_out_series: [MacroDataPoint]
    let protein_series: [ProteinDataPoint]
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
