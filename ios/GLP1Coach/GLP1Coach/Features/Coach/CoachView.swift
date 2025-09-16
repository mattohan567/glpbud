import SwiftUI

struct CoachView: View {
    @EnvironmentObject var apiClient: APIClient
    @EnvironmentObject var store: DataStore
    @State private var question = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false
    @State private var contextOptIn = true
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                            }
                            
                            if isLoading {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Coach is thinking...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                            }
                        }
                        .padding()
                        .onChange(of: messages.count) { _ in
                            withAnimation {
                                proxy.scrollTo(messages.last?.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                HStack {
                    TextField("Ask your coach...", text: $question)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            sendQuestion()
                        }
                    
                    Button(action: sendQuestion) {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(question.isEmpty || isLoading)
                }
                .padding()
            }
            .navigationTitle("Coach")
        }
        .onAppear {
            if messages.isEmpty {
                messages.append(ChatMessage(
                    role: .coach,
                    content: "Hi! I'm your agentic GLP-1 coach. I can help answer questions AND automatically log your meals, exercises, and weight when you mention them. Just tell me what you ate, how you exercised, or what you weigh! 🤖"
                ))
            }
        }
    }
    
    private func sendQuestion() {
        guard !question.isEmpty else { return }
        
        let userMessage = ChatMessage(role: .user, content: question)
        messages.append(userMessage)
        
        let currentQuestion = question
        question = ""
        
        Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                let response = try await apiClient.chatWithAgenticCoach(
                    message: currentQuestion,
                    contextOptIn: contextOptIn
                )
                
                let coachMessage = ChatMessage(
                    role: .coach,
                    content: response.message,
                    disclaimers: response.disclaimers,
                    actions: response.actions_taken
                )
                messages.append(coachMessage)
                
                // If actions were taken, refresh the today data
                if !response.actions_taken.isEmpty {
                    await store.refreshTodayStats(apiClient: apiClient)
                }
                
            } catch {
                let errorMessage = ChatMessage(
                    role: .coach,
                    content: "I'm having trouble connecting. Please try again."
                )
                messages.append(errorMessage)
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == .user ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(16)
                
                // Show action cards for logged items
                if !message.actions.isEmpty {
                    ForEach(message.actions) { action in
                        ActionCard(action: action)
                    }
                }
                
                if !message.disclaimers.isEmpty {
                    ForEach(message.disclaimers, id: \.self) { disclaimer in
                        Text(disclaimer)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .coach {
                Spacer()
            }
        }
    }
}

struct ActionCard: View {
    let action: LoggedActionResp
    
    var body: some View {
        HStack {
            // Icon based on type
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("✅ \(action.summary)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let description = details {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(8)
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var iconName: String {
        switch action.type {
        case "meal": return "fork.knife"
        case "exercise": return "figure.walk"
        case "weight": return "scalemass"
        default: return "checkmark.circle"
        }
    }
    
    private var iconColor: Color {
        switch action.type {
        case "meal": return .orange
        case "exercise": return .blue
        case "weight": return .purple
        default: return .green
        }
    }
    
    private var details: String? {
        if action.type == "meal" {
            let calories = action.details["calories"]?.value as? Int ?? 0
            let protein = action.details["protein_g"]?.value as? Double ?? 0
            return "\(calories) kcal • \(Int(protein))g protein"
        } else if action.type == "exercise" {
            let duration = action.details["duration_minutes"]?.value as? Double ?? 0
            let burned = action.details["calories_burned"]?.value as? Int ?? 0
            return "\(Int(duration)) min • \(burned) kcal burned"
        } else if action.type == "weight" {
            let weight = action.details["weight_kg"]?.value as? Double ?? 0
            return "\(String(format: "%.1f", weight)) kg"
        }
        return nil
    }
}

struct CoachSettingsView: View {
    @Binding var contextOptIn: Bool
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Privacy") {
                    Toggle("Share my data for personalized advice", isOn: $contextOptIn)
                    Text("When enabled, the coach can see your recent meals, weight, and exercise to provide more personalized guidance.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("About") {
                    Text("Your AI coach is powered by Claude and designed to help with nutrition, exercise, and general wellness questions. Always consult your healthcare provider for medical advice.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Coach Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}