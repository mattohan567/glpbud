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

// MARK: - Chat Models

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let disclaimers: [String]
    let timestamp = Date()
    
    enum Role {
        case user, coach
    }
}
