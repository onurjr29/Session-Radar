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
            } header: {
                Text("Paylaşım")
            } footer: {
                Text("Açıkken, seçtiğin repolarda aynı konu ve yeni push'lar için uyarır.")
            }
            Section {
                if repos.isEmpty {
                    Text("Bir repoda session açınca burada görünür.").foregroundStyle(.secondary)
                }
                ForEach(repos, id: \.key) { repo in
                    Toggle(repo.name, isOn: Binding(
                        get: { store.team.sharedRepos.contains(repo.key) },
                        set: { on in
                            store.team.sharedRepos.removeAll { $0 == repo.key }
                            if on { store.team.sharedRepos.append(repo.key) }
                        }))
                }
                .disabled(!store.team.enabled)
            } header: {
                Text("Paylaşılan repolar")
            } footer: {
                Text("Yalnızca seçtiğin repolarda ad, branch ve konu başlığı paylaşılır.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Açık session'lardaki tekrarsız repolar, ardından seçili ama artık açık olmayanlar
    private var repos: [(key: String, name: String)] {
        var seen = Set<String>()
        let open = store.sessions.compactMap { s -> (key: String, name: String)? in
            guard let key = s.repoKey, seen.insert(key).inserted else { return nil }
            return (key, s.repoName ?? key)
        }
        let kept = store.team.sharedRepos.filter { seen.insert($0).inserted }
            .map { (key: $0, name: $0.split(separator: "/").last.map(String.init) ?? $0) }
        return open + kept
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
