import Foundation
import Combine

enum APIError: Error, LocalizedError {
    case unauthorized
    case serverError(Int)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Your session has expired. Please log in again."
        case .serverError(let code):
            return "Server error (\(code)). Please try again."
        case .decodingError:
            return "Failed to parse response. Please try again."
        }
    }
}

@MainActor
final class APIClient: ObservableObject {
    private let base: URL
    private var authToken: String?
    private let authManager = AuthManager.shared

    // Configured JSON decoder with ISO 8601 date strategy
    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        self.base = URL(string: Config.apiBaseURL)!

        // In development, use test token if no JWT available
        #if DEBUG
        if let jwt = UserDefaults.standard.string(forKey: "supabase_jwt"), !jwt.isEmpty {
            self.authToken = jwt
        } else {
            // Use test token for development
            self.authToken = "test-token"
            print("🔧 Using test token for development")
        }
        #else
        self.authToken = UserDefaults.standard.string(forKey: "supabase_jwt")
        #endif
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
    
    func parseMealImage(imageUrl: String, hints: String? = nil) async throws -> MealParseDTO {
        struct Body: Codable {
            let image_url: String
            let hints: String?
        }
        return try await post("/parse/meal-image", Body(image_url: imageUrl, hints: hints))
    }

    func parseMealAudio(audioData: Data, hints: String? = nil) async throws -> MealParseDTO {
        struct Body: Codable {
            let audio_data: String  // base64 encoded audio
            let hints: String?
        }
        let base64Audio = audioData.base64EncodedString()
        return try await post("/parse/meal-audio", Body(audio_data: base64Audio, hints: hints))
    }

    func transcribeAudio(audioData: Data) async throws -> String {
        struct Body: Codable {
            let audio_data: String  // base64 encoded audio
        }
        struct Response: Codable {
            let transcription: String
        }
        let base64Audio = audioData.base64EncodedString()
        let response: Response = try await post("/transcribe/audio", Body(audio_data: base64Audio))
        return response.transcription
    }

    func parseExerciseText(text: String, hints: String? = nil) async throws -> ExerciseParseDTO {
        struct Body: Codable {
            let text: String
            let hints: String?
        }
        return try await post("/parse/exercise-text", Body(text: text, hints: hints))
    }

    func parseExerciseAudio(audioData: Data, hints: String? = nil) async throws -> ExerciseParseDTO {
        struct Body: Codable {
            let audio_data: String  // base64 encoded audio
            let hints: String?
        }
        let base64Audio = audioData.base64EncodedString()
        return try await post("/parse/exercise-audio", Body(audio_data: base64Audio, hints: hints))
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
    
    func askCoach(question: String, contextOptIn: Bool = false) async throws -> CoachResp {
        struct Body: Codable {
            let question: String
            let context_opt_in: Bool
        }
        return try await post("/coach/ask", Body(question: question, context_opt_in: contextOptIn))
    }
    
    func chatWithAgenticCoach(message: String, contextOptIn: Bool = true) async throws -> AgenticCoachResp {
        let body = CoachChatReq(message: message, context_opt_in: contextOptIn)
        return try await post("/coach/chat", body)
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
    
    // MARK: - History Endpoints
    
    func getHistory(limit: Int = 50, offset: Int = 0, typeFilter: String? = nil) async throws -> HistoryResp {
        var urlString = "/history?limit=\(limit)&offset=\(offset)"
        if let typeFilter = typeFilter {
            urlString += "&type_filter=\(typeFilter)"
        }
        return try await get(urlString)
    }
    
    func updateMeal(entryId: String, items: [MealItemDTO], notes: String?) async throws -> IdResp {
        let body = UpdateMealReq(items: items, notes: notes)
        return try await put("/history/meal/\(entryId)", body)
    }
    
    func updateExercise(entryId: String, type: String, durationMin: Double, intensity: String?, estKcal: Int?) async throws -> IdResp {
        let body = UpdateExerciseReq(type: type, duration_min: durationMin, intensity: intensity, est_kcal: estKcal)
        return try await put("/history/exercise/\(entryId)", body)
    }
    
    func updateWeight(entryId: String, weightKg: Double, method: String) async throws -> IdResp {
        let body = UpdateWeightReq(weight_kg: weightKg, method: method)
        return try await put("/history/weight/\(entryId)", body)
    }
    
    func deleteEntry(entryType: String, entryId: String) async throws {
        struct DeleteResp: Codable {
            let message: String
        }
        let _: DeleteResp = try await delete("/history/\(entryType)/\(entryId)")
    }
    
    // MARK: - Network Helpers

    private func handleUnauthorized() async throws {
        print("🔐 Received 401 - attempting token refresh")
        await authManager.handleTokenExpiry()

        // Get the refreshed token
        if let newToken = await authManager.getAccessToken() {
            self.authToken = newToken
            print("✅ Token refreshed successfully")
        } else {
            print("❌ Token refresh failed - user will be signed out")
            throw APIError.unauthorized
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: base.absoluteString + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for HTTP errors
        if let httpResponse = response as? HTTPURLResponse {
            print("📡 GET \(path) - Status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                // Try to refresh token and retry once
                try await handleUnauthorized()

                // Retry the request with new token
                var retryRequest = URLRequest(url: url)
                retryRequest.httpMethod = "GET"
                if let token = authToken {
                    retryRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }

                let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)

                if let retryHttpResponse = retryResponse as? HTTPURLResponse {
                    print("📡 GET \(path) RETRY - Status: \(retryHttpResponse.statusCode)")
                    if retryHttpResponse.statusCode == 401 {
                        throw APIError.unauthorized
                    } else if retryHttpResponse.statusCode >= 400 {
                        if let errorString = String(data: retryData, encoding: .utf8) {
                            print("❌ Retry error response: \(errorString)")
                        }
                        throw APIError.serverError(retryHttpResponse.statusCode)
                    }
                }

                // Use retry data for decoding
                do {
                    return try jsonDecoder.decode(T.self, from: retryData)
                } catch {
                    print("❌ Decoding error for \(path) (retry): \(error)")
                    if let responseString = String(data: retryData, encoding: .utf8) {
                        print("Response was: \(responseString)")
                    }
                    throw APIError.decodingError
                }
            } else if httpResponse.statusCode >= 400 {
                // Log error response for debugging
                if let errorString = String(data: data, encoding: .utf8) {
                    print("❌ Error response: \(errorString)")
                }
                throw APIError.serverError(httpResponse.statusCode)
            }
        }
        
        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            print("❌ Decoding error for \(path): \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("Response was: \(responseString)")
            }
            throw APIError.decodingError
        }
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
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for HTTP errors
        if let httpResponse = response as? HTTPURLResponse {
            print("📡 POST \(path) - Status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                // Try to refresh token and retry once
                try await handleUnauthorized()

                // Retry the request with new token
                var retryRequest = URLRequest(url: url)
                retryRequest.httpMethod = "POST"
                retryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let token = authToken {
                    retryRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                retryRequest.httpBody = try JSONEncoder().encode(body)

                let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)

                if let retryHttpResponse = retryResponse as? HTTPURLResponse {
                    print("📡 POST \(path) RETRY - Status: \(retryHttpResponse.statusCode)")
                    if retryHttpResponse.statusCode == 401 {
                        throw APIError.unauthorized
                    } else if retryHttpResponse.statusCode >= 400 {
                        if let errorString = String(data: retryData, encoding: .utf8) {
                            print("❌ Retry error response: \(errorString)")
                        }
                        throw APIError.serverError(retryHttpResponse.statusCode)
                    }
                }

                // Use retry data for decoding
                do {
                    return try jsonDecoder.decode(T.self, from: retryData)
                } catch {
                    print("❌ Decoding error for \(path) (retry): \(error)")
                    if let responseString = String(data: retryData, encoding: .utf8) {
                        print("Response was: \(responseString)")
                    }
                    throw APIError.decodingError
                }
            } else if httpResponse.statusCode >= 400 {
                // Log error response for debugging
                if let errorString = String(data: data, encoding: .utf8) {
                    print("❌ Error response: \(errorString)")
                }
                throw APIError.serverError(httpResponse.statusCode)
            }
        }
        
        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            print("❌ Decoding error for \(path): \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("Response was: \(responseString)")
            }
            throw APIError.decodingError
        }
    }
    
    private func put<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        let url = URL(string: base.absoluteString + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for HTTP errors
        if let httpResponse = response as? HTTPURLResponse {
            print("📡 PUT \(path) - Status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            } else if httpResponse.statusCode >= 400 {
                // Log error response for debugging
                if let errorString = String(data: data, encoding: .utf8) {
                    print("❌ Error response: \(errorString)")
                }
                throw APIError.serverError(httpResponse.statusCode)
            }
        }
        
        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            print("❌ Decoding error for \(path): \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("Response was: \(responseString)")
            }
            throw APIError.decodingError
        }
    }
    
    private func delete<T: Decodable>(_ path: String) async throws -> T {
        let url = URL(string: base.absoluteString + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for HTTP errors
        if let httpResponse = response as? HTTPURLResponse {
            print("📡 PUT \(path) - Status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            } else if httpResponse.statusCode >= 400 {
                // Log error response for debugging
                if let errorString = String(data: data, encoding: .utf8) {
                    print("❌ Error response: \(errorString)")
                }
                throw APIError.serverError(httpResponse.statusCode)
            }
        }
        
        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            print("❌ Decoding error for \(path): \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("Response was: \(responseString)")
            }
            throw APIError.decodingError
        }
    }
}