import SwiftUI
import UniformTypeIdentifiers
import UIKit
import AuthenticationServices
import Security

@main
struct DualIPAWrapperApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct GuestApp: Identifiable, Codable, Hashable {
    let id: UUID
    let fileName: String
    let displayName: String
    let version: String
    let importedAt: Date
    let storedFileName: String
}

struct EnterpriseCertificate: Identifiable, Hashable {
    let id = UUID()
    let name: String
}

let enterpriseCertificates = [
    "Aramco Services Company",
    "CENTRAL POWER INFORMATION TECHNOLOGY COMPANY",
    "China Telecom Corporation Limited",
    "HSBC Bank plc",
    "Jiangsu Simcere Pharmaceutical Co. Ltd",
    "Moving Increasingly Interconnected Technology Co. Ltd",
    "VIETNAM-NEWPV"
].map(EnterpriseCertificate.init(name:))

struct AppleSignInButton: UIViewRepresentable {
    let onCompletion: (Result<ASAuthorizationAppleIDCredential, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        button.cornerRadius = 12
        button.addTarget(context.coordinator, action: #selector(Coordinator.signIn), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    final class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let parent: AppleSignInButton
        var controller: ASAuthorizationController?

        init(_ parent: AppleSignInButton) { self.parent = parent }

        @objc func signIn() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            self.controller = nil
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            DispatchQueue.main.async { self.parent.onCompletion(.success(credential)) }
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            self.controller = nil
            DispatchQueue.main.async { self.parent.onCompletion(.failure(error)) }
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.first?.windows.first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }
    }
}

struct IPAPicker: UIViewControllerRepresentable {
    let picked: ([URL]) -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item])
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: IPAPicker
        init(_ parent: IPAPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.picked(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.cancel()
        }
    }
}

struct FilePicker: UIViewControllerRepresentable {
    let allowedExtensions: Set<String>
    let picked: (URL) -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item])
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FilePicker
        init(_ parent: FilePicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first, parent.allowedExtensions.contains(url.pathExtension.lowercased()) else { return }
            parent.picked(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.cancel()
        }
    }
}

struct CertificateSelectionView: View {
    @Binding var selected: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button(selected.count == enterpriseCertificates.count ? "Deselect All" : "Select All") {
                    if selected.count == enterpriseCertificates.count {
                        selected.removeAll()
                    } else {
                        selected = Set(enterpriseCertificates.map(\.name))
                    }
                }

                Section("Enterprise Certificates") {
                    ForEach(enterpriseCertificates) { certificate in
                        Button {
                            if selected.contains(certificate.name) {
                                selected.remove(certificate.name)
                            } else {
                                selected.insert(certificate.name)
                            }
                        } label: {
                            HStack {
                                Text(certificate.name)
                                Spacer()
                                Image(systemName: selected.contains(certificate.name) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(certificate.name) ? Color.accentColor : Color.secondary)
                            }
                        }
                    }
                }

                Text("Use only certificates you are authorized to use. This screen selects certificate identities; it does not expose private signing keys.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Certificates")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

final class PasswordStore {
    static let shared = PasswordStore()
    private let service = "DualIPA.P12"

    func set(_ password: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "password"
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    func get() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "password",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct SigningSettingsView: View {
    @AppStorage("signingURL") private var signingURL = "https://flarestore.app/api/sign"
    @AppStorage("p12Name") private var p12Name = ""
    @AppStorage("provisionName") private var provisionName = ""
    @State private var password = ""
    @State private var pickingP12 = false
    @State private var pickingProvision = false
    @Environment(\.dismiss) private var dismiss

    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DualIPA/SigningAssets", isDirectory: true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Signing API") {
                    TextField("API URL", text: $signingURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Use an authorized signing endpoint that accepts your IPA, P12, provisioning profile, and password.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Authorized signing assets") {
                    Button("Import P12" + (p12Name.isEmpty ? "" : " ✓")) { pickingP12 = true }
                    Button("Import mobileprovision" + (provisionName.isEmpty ? "" : " ✓")) { pickingProvision = true }
                    SecureField("P12 password (optional)", text: $password)
                }

                Text("The signing assets are uploaded only when you explicitly press Sign & Launch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Signing Service")
            .toolbar { Button("Done") { PasswordStore.shared.set(password); dismiss() } }
            .sheet(isPresented: $pickingP12) {
                FilePicker(allowedExtensions: ["p12", "pfx"], picked: { url in
                    pickingP12 = false
                    save(url, as: "signing.p12")
                    p12Name = url.lastPathComponent
                }, cancel: { pickingP12 = false })
            }
            .sheet(isPresented: $pickingProvision) {
                FilePicker(allowedExtensions: ["mobileprovision"], picked: { url in
                    pickingProvision = false
                    save(url, as: "signing.mobileprovision")
                    provisionName = url.lastPathComponent
                }, cancel: { pickingProvision = false })
            }
            .onAppear { password = PasswordStore.shared.get() }
        }
    }

    private func save(_ source: URL, as name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.copyItem(at: source, to: destination)
    }
}

struct ContentView: View {
    @AppStorage("appleSignedIn") private var appleSignedIn = false
    @AppStorage("enterpriseMode") private var enterpriseMode = false
    @State private var apps: [GuestApp] = []
    @State private var showingImporter = false
    @State private var showingCertificates = false
    @State private var showingSigningSettings = false
    @State private var selectedCertificates: Set<String> = []
    @State private var selectedApp: GuestApp?
    @State private var message = ""
    @State private var signing = false

    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DualIPA", isDirectory: true)
    }

    var body: some View {
        Group {
            if appleSignedIn || enterpriseMode {
                libraryView
            } else {
                loginView
            }
        }
        .preferredColorScheme(.dark)
        .task { loadApps() }
    }

    private var loginView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 64))
            Text("Dual IPA").font(.largeTitle.bold())
            AppleSignInButton { result in
                switch result {
                case .success:
                    appleSignedIn = true
                    enterpriseMode = false
                case .failure:
                    message = "Apple sign-in failed."
                }
            }
            .frame(height: 52)
            .padding()
            Button("Use Enterprise Certificates") {
                enterpriseMode = true
                appleSignedIn = false
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .alert("Dual IPA", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) {
            Button("OK") {}
        } message: {
            Text(message)
        }
    }

    private var libraryView: some View {
        NavigationStack {
            Group {
                if apps.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 44))
                        Text("No Apps").font(.title2.bold())
                        Text("Import an IPA to begin.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(apps) { item in
                            Button { selectedApp = item } label: {
                                HStack {
                                    Image(systemName: "app.fill")
                                    Text(item.displayName)
                                    Spacer()
                                    Text("Launch").foregroundStyle(.tint)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            apps.remove(atOffsets: offsets)
                            saveApps()
                        }
                    }
                }
            }
            .navigationTitle("Dual IPA")
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingImporter) {
                IPAPicker(picked: { urls in
                    showingImporter = false
                    importIPAs(urls)
                }, cancel: { showingImporter = false })
            }
            .sheet(isPresented: $showingCertificates) {
                CertificateSelectionView(selected: $selectedCertificates)
            }
            .sheet(isPresented: $showingSigningSettings) {
                SigningSettingsView()
            }
            .sheet(item: $selectedApp) { item in
                LaunchView(app: item, enterprise: enterpriseMode, certificates: selectedCertificates, signing: $signing) { text in
                    message = text
                }
            }
            .alert("Dual IPA", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) {
                Button("OK") {}
            } message: {
                Text(message)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingImporter = true } label: { Image(systemName: "plus") }
        }
        if enterpriseMode {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCertificates = true } label: {
                    Label("Certificates", systemImage: "checkmark.seal")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSigningSettings = true } label: {
                    Image(systemName: "server.rack")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Sign Out") {
                appleSignedIn = false
                enterpriseMode = false
            }
        }
    }

    private func importIPAs(_ urls: [URL]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), data.count > 4,
                  data[0] == 0x50, data[1] == 0x4B else { continue }
            let id = UUID()
            let stored = "\(id).ipa"
            try? data.write(to: directory.appendingPathComponent(stored), options: .atomic)
            apps.append(GuestApp(id: id, fileName: url.lastPathComponent, displayName: url.deletingPathExtension().lastPathComponent, version: "Imported", importedAt: Date(), storedFileName: stored))
        }
        saveApps()
    }

    private func saveApps() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(apps).write(to: directory.appendingPathComponent("apps.json"), options: .atomic)
    }

    private func loadApps() {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("apps.json")),
              let decoded = try? JSONDecoder().decode([GuestApp].self, from: data) else { return }
        apps = decoded
    }
}

struct LaunchView: View {
    let app: GuestApp
    let enterprise: Bool
    let certificates: Set<String>
    @Binding var signing: Bool
    let message: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DualIPA", isDirectory: true)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "app.fill").font(.system(size: 64))
                Text(app.displayName).font(.title.bold())
                if enterprise {
                    Text(certificates.count == 1 ? "Certificate selected" : "Select exactly one certificate")
                        .foregroundStyle(certificates.count == 1 ? Color.secondary : Color.orange)
                    Button { signAndLaunch() } label: {
                        Label(signing ? "Signing…" : "Sign & Launch", systemImage: "signature")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(signing)
                } else {
                    Text("Imported IPA")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Launch")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func signAndLaunch() {
        guard certificates.count == 1 else {
            message("Select exactly one authorized certificate.")
            return
        }

        let assets = base.appendingPathComponent("SigningAssets", isDirectory: true)
        let p12 = assets.appendingPathComponent("signing.p12")
        let provision = assets.appendingPathComponent("signing.mobileprovision")
        let ipa = base.appendingPathComponent(app.storedFileName)

        guard FileManager.default.fileExists(atPath: p12.path), FileManager.default.fileExists(atPath: provision.path) else {
            message("Import your authorized P12 and mobileprovision in Signing Service settings first.")
            return
        }

        guard let ipaData = try? Data(contentsOf: ipa),
              let p12Data = try? Data(contentsOf: p12),
              let provisionData = try? Data(contentsOf: provision),
              let endpointString = UserDefaults.standard.string(forKey: "signingURL"),
              let endpoint = URL(string: endpointString),
              endpoint.scheme?.lowercased() == "https" else {
            message("Signing configuration is invalid.")
            return
        }

        signing = true
        let boundary = "DualIPA-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }

        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"certificate\"\r\n\r\n\(certificates.first!)\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"ipa\"; filename=\"app.ipa\"\r\nContent-Type: application/octet-stream\r\n\r\n")
        body.append(ipaData)
        append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"p12\"; filename=\"signing.p12\"\r\nContent-Type: application/x-pkcs12\r\n\r\n")
        body.append(p12Data)
        append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"provision\"; filename=\"signing.mobileprovision\"\r\nContent-Type: application/octet-stream\r\n\r\n")
        body.append(provisionData)
        let password = PasswordStore.shared.get()
        if !password.isEmpty {
            append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"p12_password\"\r\n\r\n\(password)\r\n")
        }
        append("--\(boundary)--\r\n")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                signing = false
                if let error {
                    message("Signing failed: \(error.localizedDescription)")
                    return
                }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                    message("Signing service returned an error.")
                    return
                }

                if let result = try? JSONDecoder().decode(SigningResult.self, from: data), let installURLString = result.installURL,
                   let installURL = URL(string: installURLString) {
                    UIApplication.shared.open(installURL)
                    message("Signing finished. Installation page opened.")
                    return
                }

                if data.count > 4, data[0] == 0x50, data[1] == 0x4B, data[2] == 0x03, data[3] == 0x04 {
                    let output = base.appendingPathComponent("signed-\(UUID().uuidString).ipa")
                    do {
                        try data.write(to: output, options: .atomic)
                        message("Signed IPA received and saved in the app.")
                    } catch {
                        message("Signed IPA received but could not be saved: \(error.localizedDescription)")
                    }
                    return
                }

                message("Signing service returned an unexpected response.")
            }
        }.resume()
    }

    struct SigningResult: Decodable {
        let installURL: String?
        enum CodingKeys: String, CodingKey { case installURL = "install_url" }
    }
}
