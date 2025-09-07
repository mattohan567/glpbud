import SwiftUI

struct CoachView: View {
    @EnvironmentObject var apiClient: APIClient
    @State private var question = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading = false
    
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Tips") {
                        showTips()
                    }
                }
            }
        }
        .onAppear {
            if messages.isEmpty {
                messages.append(ChatMessage(
                    role: .coach,
                    content: "Hi! I'm your GLP-1 coach. I can help with nutrition, exercise, and general wellness questions. How can I help you today?",
                    disclaimers: []
                ))
            }
        }
    }
    
    private func sendQuestion() {
        guard !question.isEmpty else { return }
        
        let userMessage = ChatMessage(role: .user, content: question, disclaimers: [])
        messages.append(userMessage)
        
        let currentQuestion = question
        question = ""
        
        Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                let response = try await apiClient.askCoach(question: currentQuestion)
                let coachMessage = ChatMessage(
                    role: .coach,
                    content: response.answer,
                    disclaimers: response.disclaimers
                )
                messages.append(coachMessage)
            } catch {
                let errorMessage = ChatMessage(
                    role: .coach,
                    content: "I'm having trouble connecting right now. Please try again.",
                    disclaimers: []
                )
                messages.append(errorMessage)
            }
        }
    }
    
    private func showTips() {
        let tips = [
            "Hydrate: target ~30-35 ml/kg/day; sip throughout day",
            "Protein anchor each meal (≥25-35g) for satiety & lean mass",
            "Fiber (vegetables, beans, berries) to ease constipation risk",
            "Small portions, eat slowly; GLP-1 slows gastric emptying",
            "Gentle movement after meals (10-15 min walk) helps glucose"
        ]
        
        let tipMessage = ChatMessage(
            role: .coach,
            content: "Here are some helpful tips:\n\n" + tips.map { "• \($0)" }.joined(separator: "\n"),
            disclaimers: []
        )
        messages.append(tipMessage)
    }
}

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

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == .user ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(16)
                
                if !message.disclaimers.isEmpty {
                    ForEach(message.disclaimers, id: \.self) { disclaimer in
                        Text(disclaimer)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                    }
                }
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .coach {
                Spacer()
            }
        }
    }
}