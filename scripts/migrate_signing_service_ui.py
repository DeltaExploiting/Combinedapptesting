from pathlib import Path
import re

p = Path('DualIPAWrapper/ContentView.swift')
s = p.read_text()
s = re.sub(r'struct EnterpriseCertificate: Identifiable, Hashable \{.*?\n\]\n\n', '', s, count=1, flags=re.S)
s = re.sub(r'struct CertificateSelectionView: View \{.*?\n\}\n\nfinal class PasswordStore \{.*?\n\}\n\n', '', s, count=1, flags=re.S)
s = re.sub(r'struct SigningSettingsView: View \{.*?\n\}\n\nstruct ContentView', '''struct SigningSettingsView: View {
    @AppStorage("signingURL") private var signingURL = "https://flarestore.app/api/sign"
    @AppStorage("signingToken") private var signingToken = ""
    @Environment(\\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Signing Service") {
                    TextField("API URL", text: $signingURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Service token (optional)", text: $signingToken)
                    Text("Certificates, private signing keys, provisioning profiles, and passwords stay on the authorized signing server. This app only sends the IPA and selected certificate name.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Signing Service")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct ContentView''', s, count=1, flags=re.S)
s = s.replace('CertificateSelectionView(selected: $selectedCertificates)', 'RemoteCertificateSelectionView(available: availableCertificates, selected: $selectedCertificates)')
s = s.replace('@State private var selectedCertificates: Set<String> = []', '@State private var selectedCertificates: Set<String> = []\n    @State private var availableCertificates: [String] = []')
s = s.replace('.task { loadApps() }', '.task { loadApps(); loadCertificates() }', 1)
remote_view = '''struct RemoteCertificateSelectionView: View {
    let available: [String]
    @Binding var selected: Set<String>
    @Environment(\\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if available.isEmpty {
                    Text("No certificates are currently available from the signing service.")
                        .foregroundStyle(.secondary)
                } else {
                    Section("Certificates from signing service") {
                        ForEach(available, id: \\.self) { name in
                            Button {
                                selected = selected.contains(name) ? [] : [name]
                            } label: {
                                HStack {
                                    Text(name)
                                    Spacer()
                                    Image(systemName: selected.contains(name) ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        }
                    }
                }
                Text("Private signing keys never leave the authorized signing server.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Certificates")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

'''
s = s.replace('struct ContentView: View {', remote_view + 'struct ContentView: View {', 1)
loader = '''    private func loadCertificates() {
        guard let raw = UserDefaults.standard.string(forKey: "signingURL"),
              let base = URL(string: raw), base.scheme?.lowercased() == "https" else { return }
        var request = URLRequest(url: base.appendingPathComponent("certificates"))
        if let token = UserDefaults.standard.string(forKey: "signingToken"), !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let result = try? JSONDecoder().decode(CertificateList.self, from: data) else { return }
            DispatchQueue.main.async {
                availableCertificates = result.certificates
                if let selected = selectedCertificates.first, !result.certificates.contains(selected) { selectedCertificates.removeAll() }
            }
        }.resume()
    }
    private struct CertificateList: Decodable { let certificates: [String] }

'''
s = s.replace('    private func importIPAs(_ urls: [URL]) {', loader + '    private func importIPAs(_ urls: [URL]) {', 1)
start = s.index('    private func signAndLaunch() {')
end = s.index('    struct SigningResult: Decodable', start)
new_method = '''    private func signAndLaunch() {
        guard certificates.count == 1, let certificate = certificates.first else {
            message("Select exactly one certificate provided by the signing service.")
            return
        }
        let ipa = base.appendingPathComponent(app.storedFileName)
        guard let ipaData = try? Data(contentsOf: ipa),
              let endpointString = UserDefaults.standard.string(forKey: "signingURL"),
              let endpoint = URL(string: endpointString), endpoint.scheme?.lowercased() == "https" else {
            message("Signing service configuration is invalid.")
            return
        }
        signing = true
        let boundary = "DualIPA-\\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = UserDefaults.standard.string(forKey: "signingToken"), !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "Authorization")
        }
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        append("--\\(boundary)\\r\\nContent-Disposition: form-data; name=\\"certificate\\"\\r\\n\\r\\n\\(certificate)\\r\\n")
        append("--\\(boundary)\\r\\nContent-Disposition: form-data; name=\\"ipa\\"; filename=\\"app.ipa\\"\\r\\nContent-Type: application/octet-stream\\r\\n\\r\\n")
        body.append(ipaData)
        append("\\r\\n--\\(boundary)--\\r\\n")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                signing = false
                if let error { message("Signing failed: \\(error.localizedDescription)"); return }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                    message("Signing service returned an error."); return
                }
                if let result = try? JSONDecoder().decode(SigningResult.self, from: data), let installURLString = result.installURL,
                   let installURL = URL(string: installURLString) {
                    UIApplication.shared.open(installURL)
                    message("Signing finished. Installation page opened.")
                    return
                }
                message("Signing service returned an unexpected response.")
            }
        }.resume()
    }

'''
s = s[:start] + new_method + s[end:]
p.write_text(s)
