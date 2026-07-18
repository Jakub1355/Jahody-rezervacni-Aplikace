import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var errorMessage: String?
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image("StrawberryLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
            Text("Jahody")
                .font(.largeTitle.bold())
            Text("Objednávky z farmy pro celou rodinu")
                .foregroundStyle(.secondary)
            Spacer()

            Button {
                signIn()
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle")
                    Text("Přihlásit se účtem Google")
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSigningIn)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Text("Aplikace je jen pro povolené rodinné účty.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private func signIn() {
        errorMessage = nil
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await auth.signIn()
            } catch is CancellationError {
                // Uživatel přihlášení zavřel.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
