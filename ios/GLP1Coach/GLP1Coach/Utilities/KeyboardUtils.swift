import SwiftUI
import UIKit

// MARK: - Keyboard Dismissal Utilities
extension UIApplication {
    /// Dismiss the keyboard by ending editing for all windows
    func hideKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Keyboard Toolbar Modifier
struct KeyboardToolbar: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            action()
                        }
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                    }
                }
            }
    }
}

extension View {
    /// Add a "Done" button to the keyboard toolbar
    func keyboardToolbar(action: @escaping () -> Void = { UIApplication.shared.hideKeyboard() }) -> some View {
        modifier(KeyboardToolbar(action: action))
    }

    /// Alternative keyboard toolbar that uses a simpler approach to avoid conflicts
    func safeKeyboardToolbar(action: @escaping () -> Void = { UIApplication.shared.hideKeyboard() }) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                // Keyboard is showing - toolbar will be handled by SwiftUI
            }
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        action()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
    }

    /// Specialized toolbar for numeric input fields to minimize conflicts
    func numericKeyboardToolbar(action: @escaping () -> Void = { UIApplication.shared.hideKeyboard() }) -> some View {
        self
            .onSubmit {
                action()
            }
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        action()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                }
            }
    }
}

// MARK: - Tap to Dismiss Keyboard Modifier
struct TapToDismissKeyboard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                UIApplication.shared.hideKeyboard()
            }
    }
}

extension View {
    /// Allow tapping anywhere to dismiss the keyboard
    func tapToDismissKeyboard() -> some View {
        modifier(TapToDismissKeyboard())
    }
}

// MARK: - Focus State Helpers
extension View {
    /// Dismiss keyboard when this view appears
    func dismissKeyboardOnAppear() -> some View {
        onAppear {
            UIApplication.shared.hideKeyboard()
        }
    }

    /// Safely dismiss keyboard when view disappears to prevent session issues
    func dismissKeyboardOnDisappear() -> some View {
        onDisappear {
            UIApplication.shared.hideKeyboard()
        }
    }

    /// Complete keyboard management (appear + disappear)
    func manageKeyboard() -> some View {
        self
            .dismissKeyboardOnAppear()
            .dismissKeyboardOnDisappear()
    }
}