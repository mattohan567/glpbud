import SwiftUI

struct AuthView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea(.all)

            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.spacing.xxl) {
                    // Hero Section
                    VStack(spacing: Theme.spacing.md) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.white)
                            .shadow(radius: 20, y: 10)

                        Text("GLP-1 Coach")
                            .font(.heroTitle)
                            .foregroundStyle(.white)

                        Text("Track meals, weight & habits with AI assist")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)
                    .padding(.bottom, 20)

                    // Auth Form
                    GlassCard {
                        VStack(spacing: Theme.spacing.lg) {
                            // Form Fields
                            VStack(spacing: Theme.spacing.md) {
                                TextField("Email", text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .textFieldStyle(.roundedBorder)

                                SecureField("Password", text: $password)
                                    .textContentType(.password)
                                    .textFieldStyle(.roundedBorder)

                                if isSignUp {
                                    SecureField("Confirm Password", text: $confirmPassword)
                                        .textContentType(.password)
                                        .textFieldStyle(.roundedBorder)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }

                            // Primary Action Button
                            PrimaryButton(
                                title: isSignUp ? "Create Account" : "Sign In",
                                isLoading: isLoading
                            ) {
                                handleAuth()
                            }
                            .disabled(!isFormValid)

                            // Divider
                            HStack {
                                Rectangle()
                                    .frame(height: 1)
                                    .opacity(0.2)
                                Text("or")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                                Rectangle()
                                    .frame(height: 1)
                                    .opacity(0.2)
                            }

                            // Social Login Buttons
                            VStack(spacing: Theme.spacing.sm) {
                                SocialButton(icon: "applelogo", title: "Continue with Apple") {
                                    // Handle Apple sign in
                                }

                                SocialButton(icon: "globe", title: "Continue with Google") {
                                    // Handle Google sign in
                                }
                            }

                            // Toggle Sign Up / Sign In
                            Button(action: {
                                withAnimation(Theme.springAnimation) {
                                    isSignUp.toggle()
                                }
                            }) {
                                Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.8))
                            }

                            #if DEBUG
                            Button(action: useTestAccount) {
                                Text("Use Test Account")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            #endif
                        }
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 60)
                }
            }
        }
        .navigationBarHidden(true)
        .alert("Authentication", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .tapToDismissKeyboard()
    }
    
    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && 
        (!isSignUp || password == confirmPassword) &&
        email.contains("@")
    }
    
    private func handleAuth() {
        isLoading = true
        Task {
            do {
                if isSignUp {
                    try await authManager.signUp(email: email, password: password)
                } else {
                    try await authManager.signIn(email: email, password: password)
                }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    showingAlert = true
                    isLoading = false
                }
            }
        }
    }
    
    private func useTestAccount() {
        email = Config.testEmail
        password = Config.testPassword
        handleAuth()
    }
}