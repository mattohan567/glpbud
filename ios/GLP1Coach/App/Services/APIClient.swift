import Foundation
import Combine

@MainActor
final class APIClient: ObservableObject {
    private let base: URL
    private var tokenProvider: () -> String? = {
        UserDefaults.standard.string(forKey: "supabase_jwt")
    }
    
    init() {
        let baseURL = ProcessInfo.processInfo.environment["API_BASE"] ?? "https://api.glp1coach.com"
        self.base = URL(string: baseURL)!
    }
    
    // MARK: - Parse Endpoints
    
    func parseMealImage(imageURL: URL, hints: String?) async throws -> MealParseDTO {
        struct Body: Codable {
            let image_url: String
            let hints: String?
        }
        return try await post("/parse/meal-image", Body(image_url: imageURL.absoluteString, hints: hints))
    }
    
    func parseMealText(text: String, hints: String?) async throws -> MealParseDTO {
        struct Body: Codable {
            let text: String
            let hints: String?
        }
        return try await post("/parse/meal-text", Body(text: text, hints: hints))
    }
    
    // MARK: - Logging Endpoints
    
    func logMeal(ts: Date, source: String, parse: MealParseDTO, notes: String?) async throws -> IdResp {
        struct Body: Codable {
            let datetime: String
            let source: String
            let parse: MealParseDTO
            let notes: String?
        }
        let iso = ISO8601DateFormatter().string(from: ts)
        return try await post("/log/meal", Body(datetime: iso, source: source, parse: parse, notes: notes))
    }
    
    func logExercise(ts: Date, type: String, duration: Double, intensity: String?, kcal: Int?) async throws -> IdResp {
        struct Body: Codable {
            let datetime: String
            let type: String
            let duration_min: Double
            let intensity: String?
            let est_kcal: Int?
        }
        let iso = ISO8601DateFormatter().string(from: ts)
        return try await post("/log/exercise", Body(
            datetime: iso,
            type: type,
            duration_min: duration,
            intensity: intensity,
            est_kcal: kcal
        ))
    }
    
    func logWeight(ts: Date, weight_kg: Double, method: String) async throws -> IdResp {
        struct Body: Codable {
            let datetime: String
            let weight_kg: Double
            let method: String
        }
        let iso = ISO8601DateFormatter().string(from: ts)
        return try await post("/log/weight", Body(datetime: iso, weight_kg: weight_kg, method: method))
    }
    
    func scheduleMedication(drug: String, dose: Double, schedule: String, start: Date, notes: String?) async throws -> IdResp {
        struct Body: Codable {
            let drug_name: String
            let dose_mg: Double
            let schedule_rule: String
            let start_ts: String
            let notes: String?
        }
        let iso = ISO8601DateFormatter().string(from: start)
        return try await post("/med/schedule", Body(
            drug_name: drug,
            dose_mg: dose,
            schedule_rule: schedule,
            start_ts: iso,
            notes: notes
        ))
    }
    
    func logMedEvent(ts: Date, drug: String, dose: Double, site: String?, effects: [String]?, notes: String?) async throws -> IdResp {
        struct Body: Codable {
            let datetime: String
            let drug_name: String
            let dose_mg: Double
            let injection_site: String?
            let side_effects: [String]?
            let notes: String?
        }
        let iso = ISO8601DateFormatter().string(from: ts)
        return try await post("/log/med", Body(
            datetime: iso,
            drug_name: drug,
            dose_mg: dose,
            injection_site: site,
            side_effects: effects,
            notes: notes
        ))
    }
    
    // MARK: - Query Endpoints
    
    func getToday() async throws -> TodayResp {
        try await get("/today")
    }
    
    func getTrends(range: String = "7d") async throws -> TrendsResp {
        try await get("/trends?range=\(range)")
    }
    
    func askCoach(question: String, includeContext: Bool = true) async throws -> CoachResp {
        struct Body: Codable {
            let question: String
            let context_opt_in: Bool
        }
        return try await post("/coach/ask", Body(question: question, context_opt_in: includeContext))
    }
    
    func getNextMedDose() async throws -> Date? {
        struct Response: Codable {
            let next_dose_ts: String
        }
        let resp: Response = try await get("/med/next")
        return ISO8601DateFormatter().date(from: resp.next_dose_ts)
    }
    
    // MARK: - Generic Helpers
    
    private func request(_ path: String, method: String, body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        req.timeoutInterval = 30
        return req
    }
    
    private func post<T: Codable, R: Codable>(_ path: String, _ body: T) async throws -> R {
        let data = try JSONEncoder().encode(body)
        let (responseData, response) = try await URLSession.shared.data(for: request(path, method: "POST", body: data))
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode < 300 else {
            throw APIError.serverError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(R.self, from: responseData)
    }
    
    private func get<R: Codable>(_ path: String) async throws -> R {
        let (data, response) = try await URLSession.shared.data(for: request(path, method: "GET"))
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode < 300 else {
            throw APIError.serverError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(R.self, from: data)
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case serverError(Int)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let code):
            return "Server error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}