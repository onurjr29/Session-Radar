import RadarCore
import SwiftUI

struct TeamSettingsView: View {
    @Bindable var store: RadarStore
    @State private var email = ""
    @State private var password = ""
    @State private var signInError: String?
    @State private var signingIn = false

    var body: some View {
        Form {
            Section("Sen") {
                TextField("Adın", text: $store.team.name)
            }
            Section("Hesap") {
                if !store.teamConfigured {
                    Text("Sunucu ayarlanmamış").foregroundStyle(.secondary)
                } else if store.teamSignedIn {
                    LabeledContent("E-posta", value: store.team.email)
                    Button("Çıkış yap") { store.teamSignOut() }
                } else {
                    TextField("E-posta", text: $email).textContentType(.emailAddress)
                    SecureField("Parola", text: $password)
                    Button("Giriş yap") {
                        signingIn = true
                        Task {
                            signInError = await store.teamSignIn(email: email, password: password)
                            if signInError == nil { store.team.email = email; password = "" }
                            signingIn = false
                        }
                    }
                    .disabled(signingIn || email.isEmpty || password.isEmpty)
                    if let signInError { Text(signInError).foregroundStyle(.secondary) }
                }
            }
            Section {
                Toggle("Çakışma uyarılarını aç", isOn: $store.team.enabled)
                ForEach(repos, id: \.key) { repo in
                    Toggle(repo.name, isOn: Binding(
                        get: { store.team.sharedRepos.contains(repo.key) },
                        set: { on in
                            store.team.sharedRepos.removeAll { $0 == repo.key }
                            if on { store.team.sharedRepos.append(repo.key) }
                        }))
                }
            } header: {
                Text("Paylaşım")
            } footer: {
                Text("Yalnızca seçtiğin repolarda ad, branch ve konu başlığı paylaşılır.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Açık session'lardaki tekrarsız repolar
    private var repos: [(key: String, name: String)] {
        var seen = Set<String>()
        return store.sessions.compactMap { s in
            guard let key = s.repoKey, seen.insert(key).inserted else { return nil }
            return (key, s.repoName ?? key)
        }
    }
}

/// Sunucuya ulaşılamıyorsa görünen tek işaret.
struct SharingDownMark: View {
    var body: some View {
        Image(systemName: "person.2.slash")
            .foregroundStyle(.secondary)
            .help("Paylaşım kapalı: sunucuya ulaşılamıyor")
            .accessibilityLabel("Paylaşım kapalı: sunucuya ulaşılamıyor")
    }
}
