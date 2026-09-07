import SwiftUI
import UniformTypeIdentifiers
import UIKit
import AuthenticationServices

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
        private let parent: AppleSignInButton

        init(_ parent: AppleSignInButton) {
            self.parent = parent
        }

        @objc func signIn() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                DispatchQueue.main.async { self.parent.onCompletion(.success(credential)) }
            } else {
                DispatchQueue.main.async {
                    self.parent.onCompletion(.failure(CocoaError(.coderReadCorrupt)))
                }
            }
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            DispatchQueue.main.async { self.parent.onCompletion(.failure(error)) }
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }
    }
}

struct IPAFilePicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(documentTypes: [UTType.item.identifier], in: .import)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: IPAFilePicker

        init(_ parent: IPAFilePicker) {
            self.parent = parent
            super.init()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            DispatchQueue.main.async { self.parent.onPick(urls) }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            DispatchQueue.main.async { self.parent.onCancel() }
        }
    }
}

struct ContentView: View {
    @AppStorage("appleSignedIn") private var appleSignedIn = false
    @State private var apps: [GuestApp] = []
    @State private var showingImporter = false
    @State private var selectedApp: GuestApp?
    @State private var message = ""

    private var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DualIPA", isDirectory: true)
    }

    var body: some View {
        Group {
            if appleSignedIn {
                libraryView
            } else {
                loginView
            }
        }
        .preferredColorScheme(.dark)
        .task { loadApps() }
    }

    private var loginView: some View {
        ZStack {
            Color(red: 0.055, green: 0.055, blue: 0.07).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 70))
                Text("Dual IPA")
                    .font(.system(size: 36, weight: .bold))
                Text("Sign in with your Apple Account to continue.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                AppleSignInButton { result in
                    switch result {
                    case .success:
                        appleSignedIn = true
                    case .failure(let error):
                        message = "Apple sign-in failed: \(error.localizedDescription)"
                    }
                }
                .frame(height: 52)
                .padding(.horizontal, 28)
                Text("Your Apple Account password is handled by Apple and is never entered into Dual IPA.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 36)
                Spacer()
            }
        }
        .alert("Dual IPA", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) {
            Button("OK") { message = "" }
        } message: { Text(message) }
    }

    private var libraryView: some View {
        NavigationStack {
            Group {
                if apps.isEmpty {
                    ContentUnavailableView {
                        Label("No Apps", systemImage: "square.stack.3d.up")
                    } description: {
                        Text("Import an IPA to add it to your app library.")
                    } actions: {
                        Button("Import IPA") { showingImporter = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(apps) { app in
                            Button { selectedApp = app } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "app.fill")
                                        .font(.title2)
                                        .frame(width: 48, height: 48)
                                        .background(.thinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(app.displayName).font(.headline)
                                        Text("Version \(app.version)").font(.caption).foregroundStyle(.secondary)
                                        Text(app.fileName).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Text("Launch").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { deleteApps(at: $0) }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(red: 0.055, green: 0.055, blue: 0.07))
            .navigationTitle("Dual IPA")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingImporter = true } label: { Image(systemName: "plus") }
                    Button("Sign Out") { appleSignedIn = false }
                }
            }
            .sheet(isPresented: $showingImporter) {
                IPAFilePicker(
                    onPick: { urls in
                        showingImporter = false
                        importIPAs(urls)
                    },
                    onCancel: { showingImporter = false }
                )
                .ignoresSafeArea()
            }
            .sheet(item: $selectedApp) { GuestContainerView(app: $0) }
            .alert("Dual IPA", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) {
                Button("OK") { message = "" }
            } message: { Text(message) }
        }
    }

    private func importIPAs(_ urls: [URL]) {
        guard !urls.isEmpty else { message = "No file was selected."; return }
        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true, attributes: nil)
            var imported = 0
            var failures: [String] = []
            for url in urls {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                    guard data.count >= 4,
                          data[0] == 0x50, data[1] == 0x4B,
                          data[2] == 0x03, data[3] == 0x04 else {
                        throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "The selected file is not a valid IPA archive."])
                    }
                    let id = UUID()
                    let storedName = "\(id.uuidString).ipa"
                    try data.write(to: storageURL.appendingPathComponent(storedName), options: .atomic)
                    apps.append(GuestApp(id: id, fileName: url.lastPathComponent, displayName: url.deletingPathExtension().lastPathComponent, version: "Imported", importedAt: Date(), storedFileName: storedName))
                    imported += 1
                } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            saveApps()
            if imported == 0 { message = "Import failed.\n\(failures.joined(separator: "\n"))" }
            else if failures.isEmpty { message = "Imported \(imported) IPA file(s) successfully." }
            else { message = "Imported \(imported) IPA file(s).\n\nFailed:\n\(failures.joined(separator: "\n"))" }
        } catch { message = "Could not create the IPA library: \(error.localizedDescription)" }
    }

    private func deleteApps(at offsets: IndexSet) {
        for index in offsets {
            let app = apps[index]
            try? FileManager.default.removeItem(at: storageURL.appendingPathComponent(app.storedFileName))
        }
        apps.remove(atOffsets: offsets)
        saveApps()
    }

    private func saveApps() {
        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true, attributes: nil)
            let data = try JSONEncoder().encode(apps)
            try data.write(to: storageURL.appendingPathComponent("apps.json"), options: .atomic)
        } catch { message = "Could not save the app library: \(error.localizedDescription)" }
    }

    private func loadApps() {
        guard let data = try? Data(contentsOf: storageURL.appendingPathComponent("apps.json")),
              let saved = try? JSONDecoder().decode([GuestApp].self, from: data) else { return }
        apps = saved.filter { FileManager.default.fileExists(atPath: storageURL.appendingPathComponent($0.storedFileName).path) }
        if apps.count != saved.count { saveApps() }
    }
}

struct GuestContainerView: View {
    let app: GuestApp
    @Environment(\.dismiss) private var dismiss

    private var storedIPAURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DualIPA", isDirectory: true)
            .appendingPathComponent(app.storedFileName)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "app.fill").font(.system(size: 64)).frame(width: 110, height: 110).background(.thinMaterial).clipShape(RoundedRectangle(cornerRadius: 24))
                Text(app.displayName).font(.title.bold())
                Text("Guest app container").foregroundStyle(.secondary)
                Text(FileManager.default.fileExists(atPath: storedIPAURL.path) ? "IPA stored successfully" : "IPA file is missing").font(.footnote).foregroundStyle(.secondary)
                Text("The IPA is stored in this app's private library. Signing and installing an app still requires Apple's permitted signing and installation mechanisms.")
                    .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
                Spacer()
            }
            .padding()
            .navigationTitle("Launch")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
