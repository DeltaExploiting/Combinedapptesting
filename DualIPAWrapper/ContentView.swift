import SwiftUI
import UniformTypeIdentifiers
import UIKit

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

struct IPAFilePicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: IPAFilePicker
        init(_ parent: IPAFilePicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}

struct ContentView: View {
    @State private var apps: [GuestApp] = []
    @State private var showingImporter = false
    @State private var selectedApp: GuestApp?
    @State private var message = ""

    private var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DualIPA", isDirectory: true)
    }

    var body: some View {
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
                                        Text("Version \(app.version)")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(app.fileName)
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Text("Launch")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tint)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingImporter = true } label: { Image(systemName: "plus") }
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
            }
            .sheet(item: $selectedApp) { GuestContainerView(app: $0) }
            .alert("Dual IPA", isPresented: Binding(
                get: { !message.isEmpty },
                set: { if !$0 { message = "" } }
            )) {
                Button("OK") { message = "" }
            } message: { Text(message) }
            .task { loadApps() }
        }
        .preferredColorScheme(.dark)
    }

    private func importIPAs(_ urls: [URL]) {
        let ipaURLs = urls.filter {
            $0.isFileURL && $0.pathExtension.lowercased() == "ipa"
        }

        guard !ipaURLs.isEmpty else {
            message = "No IPA selected. Please choose a file ending in .ipa."
            return
        }

        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true, attributes: nil)
            var imported = 0
            var failures: [String] = []

            for url in ipaURLs {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

                do {
                    let id = UUID()
                    let storedName = "\(id.uuidString).ipa"
                    let destination = storageURL.appendingPathComponent(storedName)
                    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                    guard !data.isEmpty else {
                        throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "The selected IPA is empty."])
                    }
                    try data.write(to: destination, options: .atomic)

                    apps.append(GuestApp(
                        id: id,
                        fileName: url.lastPathComponent,
                        displayName: url.deletingPathExtension().lastPathComponent,
                        version: "Imported",
                        importedAt: Date(),
                        storedFileName: storedName
                    ))
                    imported += 1
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            saveApps()
            if imported == 0 {
                message = "Import failed.\n\(failures.joined(separator: "\n"))"
            } else if failures.isEmpty {
                message = "Imported \(imported) IPA file(s) successfully."
            } else {
                message = "Imported \(imported) IPA file(s).\n\nFailed:\n\(failures.joined(separator: "\n"))"
            }
        } catch {
            message = "Could not create the IPA library: \(error.localizedDescription)"
        }
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
        } catch {
            message = "Could not save the app library: \(error.localizedDescription)"
        }
    }

    private func loadApps() {
        guard let data = try? Data(contentsOf: storageURL.appendingPathComponent("apps.json")),
              let saved = try? JSONDecoder().decode([GuestApp].self, from: data) else { return }
        apps = saved.filter {
            FileManager.default.fileExists(atPath: storageURL.appendingPathComponent($0.storedFileName).path)
        }
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
                Image(systemName: "app.fill")
                    .font(.system(size: 64))
                    .frame(width: 110, height: 110)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                Text(app.displayName).font(.title.bold())
                Text("Guest app container").foregroundStyle(.secondary)
                Text(FileManager.default.fileExists(atPath: storedIPAURL.path) ? "IPA stored successfully" : "IPA file is missing")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("The imported IPA is stored in this app's private library. A normal iOS app cannot directly execute another arbitrary IPA; actual guest execution requires a LiveContainer-style runtime.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Spacer()
            }
            .padding()
            .navigationTitle("Launch")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
