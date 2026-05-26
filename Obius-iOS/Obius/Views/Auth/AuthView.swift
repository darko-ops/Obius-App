import SwiftUI

struct AuthView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var isSignUp = false

    var body: some View {
        NavigationStack {
            if authManager.isLoading && authManager.currentUser == nil {
                ProgressView("Loading...")
            } else if isSignUp {
                SignUpView(showSignIn: { isSignUp = false })
            } else {
                SignInView(showSignUp: { isSignUp = true })
            }
        }
    }
}

// MARK: - Sign In View

struct SignInView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var showingResetPassword = false

    let showSignUp: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo/Title
            VStack(spacing: 0) {
                Image("ObiusLogo")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .padding(.bottom, 20)

                Text("Obius")
                    .font(.custom("LexendExa-SemiBold", size: 34, relativeTo: .largeTitle))
                    .padding(.bottom, 2)

                Text("Architect your thoughts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Form
            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)

                if let error = authManager.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        await authManager.signIn(email: email, password: password)
                    }
                } label: {
                    if authManager.isLoading {
                        ProgressView()
                            .tint(.black)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign In")
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .disabled(email.isEmpty || password.isEmpty || authManager.isLoading)

                Button("Forgot password?") {
                    showingResetPassword = true
                }
                .font(.caption)
            }
            .padding()

            Spacer()

            // Sign up link
            HStack {
                Text("Don't have an account?")
                    .foregroundStyle(.secondary)
                Button("Sign Up") {
                    showSignUp()
                }
            }
            .font(.footnote)
            .padding(.bottom)
        }
        .padding()
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
            }
        }
        #endif
        .sheet(isPresented: $showingResetPassword) {
            ResetPasswordView()
        }
    }
}

// MARK: - Sign Up View

struct SignUpView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""

    let showSignIn: () -> Void

    var passwordsMatch: Bool {
        password == confirmPassword && !password.isEmpty
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Title
            VStack(spacing: 0) {
                Image("ObiusLogo")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .padding(.bottom, 20)

                Text("Create Account")
                    .font(.custom("LexendExa-SemiBold", size: 34, relativeTo: .largeTitle))
                    .padding(.bottom, 2)

                Text("Architect your thoughts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Form
            VStack(spacing: 16) {
                TextField("Display Name (optional)", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.name)

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)

                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.newPassword)

                if !confirmPassword.isEmpty && !passwordsMatch {
                    Text("Passwords don't match")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let error = authManager.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        await authManager.signUp(
                            email: email,
                            password: password,
                            displayName: displayName.isEmpty ? nil : displayName
                        )
                        // Show the paywall as an optional upsell — the sheet is
                        // dismissible so users can skip and upgrade later from
                        // Settings → Subscription. Onboarding seed-pending is
                        // set inside AuthManager.signUp itself to avoid racing
                        // the auth-state observer.
                        if authManager.authError == nil,
                           authManager.isAuthenticated,
                           TierManager.shared.currentTier == .free {
                            TierManager.shared.paywallFeature = nil
                            TierManager.shared.showPaywall = true
                        }
                    }
                } label: {
                    if authManager.isLoading {
                        ProgressView()
                            .tint(.black)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Create Account")
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .disabled(email.isEmpty || !passwordsMatch || authManager.isLoading)
            }
            .padding()

            Spacer()

            // Sign in link
            HStack {
                Text("Already have an account?")
                    .foregroundStyle(.secondary)
                Button("Sign In") {
                    showSignIn()
                }
            }
            .font(.footnote)
            .padding(.bottom)
        }
        .padding()
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
            }
        }
        #endif
    }
}

// MARK: - Reset Password View

struct ResetPasswordView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var email = ""
    @State private var sent = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if sent {
                    VStack(spacing: 16) {
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)

                        Text("Check your email")
                            .font(.title2.bold())

                        Text("We've sent a password reset link to \(email)")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)

                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("Reset Password")
                            .font(.title2.bold())

                        Text("Enter your email and we'll send you a reset link")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)

                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            #endif

                        if let error = authManager.authError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Button {
                            Task {
                                await authManager.sendPasswordReset(email: email)
                                sent = true
                            }
                        } label: {
                            if authManager.isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Send Reset Link")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(email.isEmpty || authManager.isLoading)
                    }
                }
            }
            .padding()
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                }
                #endif
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview("Sign In") {
    SignInView(showSignUp: {})
}

#Preview("Sign Up") {
    SignUpView(showSignIn: {})
}
