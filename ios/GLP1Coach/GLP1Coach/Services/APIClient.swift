import Foundation
import Combine

@MainActor
final class APIClient: ObservableObject {
    private let base: URL
    private var authToken: String?
    
    init() {
        self.base = URL(string: Config.apiBaseURL)!
        self.authToken = UserDefaults.standard.string(forKey: "supabase_jwt")
    }
    
    func updateAuthToken(_ token: String) {
        self.authToken = token
    }
    
    // MARK: - Parse Endpoints
    
    func parseMealText(text: String, hints: String? = nil) async throws -> MealParseDTO {
        struct Body: Codable {
            let text: String
            let hints: String?
        }
        return try await post("/parse/meal-text", Body(text: text, hints: hints))
    }
    
    func parseMealImage(imageURL: URL, hints: String? = nil) async throws -> MealParseDTO {
        struct Body: Codable {
            let image_url: String
            let hints: String?
        }
        return try await post("/parse/meal-image", Body(image_url: imageURL.absoluteString, hints: hints))
    }
    
    // MARK: - Logging Endpoints
    
    func logMeal(meal: Meal, parse: MealParseDTO) async throws -> IdResp {
        struct Body: Codable {
            let datetime: String
            let source: String
            let parse: MealParseDTO
            let notes: String?
        }
        let iso = ISO8601DateFormatter().string(from: meal.timestamp)
        return try await post("/log/meal", Body(datetime: iso, source: meal.source.rawValue, parse: parse, notes: meal.notes))
    }
    
    func logExercise(_ exercise: Exercise) async throws -> IdResp {
        struct Body: Codable {
            let datetime: String
            let type: String
            let duration_min: Double
            let intensity: String?
            let est_kcal: Int?
        }
        let iso = ISO8601DateFormatter().string(from: exercise.timestamp)
        return try await post("/log/exercise", Body(
            datetime: iso,
            type: exercise.type,
            duration_min: exercise.duration_min,
            intensity: exercise.intensity,
            est_kcal: exercise.est_kcal
        ))
    }
    
    func logWeight(_ weight: Weight) async throws -> IdResp {
        struct Body: Codable {
            let datetime: String
            let weight_kg: Double
            let method: String
        }
        let iso = ISO8601DateFormatter().string(from: weight.timestamp)
        return try await post("/log/weight", Body(
            datetime: iso,
            weight_kg: weight.weight_kg,
            method: weight.method
        ))
    }
    
    // MARK: - Query Endpoints
    
    func getToday() async throws -> TodayResp {
        return try await get("/today")
    }
    
    func getTrends(range: String) async throws -> TrendsResp {
        return try await get("/trends?range=\(range)")
    }
    
    // MARK: - Coach Endpoint
    
    func askCoach(question: String) async throws -> CoachResp {
        struct Body: Codable {
            let question: String
        }
        return try await post("/coach/ask", Body(question: question))
    }
    
    // MARK: - Medication Endpoints
    
    func getNextDose() async throws -> NextDoseResp {
        return try await get("/med/next")
    }
    
    func setMedicationSchedule(drug: String, dose: Double, schedule: String) async throws -> IdResp {
        struct Body: Codable {
            let drug_name: String
            let dose_mg: Double
            let schedule_rule: String
            let start_ts: String
        }
        let iso = ISO8601DateFormatter().string(from: Date())
        return try await post("/med/schedule", Body(
            drug_name: drug,
            dose_mg: dose,
            schedule_rule: schedule,
            start_ts: iso
        ))
    }
    
    // MARK: - Network Helpers
    
    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: base.absoluteString + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    private func post<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        let url = URL(string: base.absoluteString + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}