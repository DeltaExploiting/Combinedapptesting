import SwiftUI
import UniformTypeIdentifiers

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
                            Button {
                                selectedApp = app
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "app.fill")
                                        .font(.title2)
                                        .frame(width: 48, height: 48)
                                        .background(.thinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(app.displayName).font(.headline)
                                        Text("Version \(app.version)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(app.fileName)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Text("Launch")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            deleteApps(at: offsets)
                        }
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
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
                allowsMultipleSelection: true
            ) { result in
                importIPAs(result)
            }
            .sheet(item: $selectedApp) { app in
                GuestContainerView(app: app)
            }
            .alert("Dual IPA", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) {
                Button("OK") { message = "" }
            } message: {
                Text(message)
            }
            .task { loadApps() }
        }
        .preferredColorScheme(.dark)
    }

    private func importIPAs(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            message = "Import failed: \(error.localizedDescription)"

        case .success(let urls):
            do {
                try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)

                var imported = 0
                var failures = 0

                for url in urls where url.pathExtension.lowercased() == "ipa" {
                    let accessGranted = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessGranted { url.stopAccessingSecurityScopedResource() }
                    }

                    let id = UUID()
                    let storedName = "\(id.uuidString).ipa"
                    let destination = storageURL.appendingPathComponent(storedName)

                    do {
                        try FileManager.default.copyItem(at: url, to: destination)

                        let app = GuestApp(
                            id: id,
                            fileName: url.lastPathComponent,
                            displayName: url.deletingPathExtension().lastPathComponent,
                            version: "Imported",
                            importedAt: Date(),
                            storedFileName: storedName
                        )
                        apps.append(app)
                        imported += 1
                    } catch {
                        failures += 1
                    }
                }

                saveApps()

                if imported == 0 {
                    message = "No IPA files could be imported. Make sure the selected files are valid .ipa files."
                } else if failures > 0 {
                    message = "Imported \(imported) IPA file(s). \(failures) file(s) could not be copied."
                } else {
                    message = "Imported \(imported) IPA file(s) successfully."
                }
            } catch {
                message = "Could not create the IPA library: \(error.localizedDescription)"
            }
        }
    }

    private func deleteApps(at offsets: IndexSet) {
        for index in offsets {
            let app = apps[index]
            let file = storageURL.appendingPathComponent(app.storedFileName)
            try? FileManager.default.removeItem(at: file)
        }
        apps.remove(atOffsets: offsets)
        saveApps()
    }

    private func saveApps() {
        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(apps)
            try data.write(to: storageURL.appendingPathComponent("apps.json"), options: .atomic)
        } catch {
            message = "Could not save the app library."
        }
    }

    private func loadApps() {
        guard
            let data = try? Data(contentsOf: storageURL.appendingPathComponent("apps.json")),
            let saved = try? JSONDecoder().decode([GuestApp].self, from: data)
        else { return }

        apps = saved.filter { app in
            FileManager.default.fileExists(atPath: storageURL.appendingPathComponent(app.storedFileName).path)
        }

        if apps.count != saved.count {
            saveApps()
        }
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

                Text(app.displayName)
                    .font(.title.bold())

                Text("Guest app container")
                    .foregroundStyle(.secondary)

                Text(FileManager.default.fileExists(atPath: storedIPAURL.path) ? "IPA stored successfully" : "IPA file is missing")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("The imported IPA is now copied into the app's private library so it remains available after the file picker closes and after restarting Dual IPA. Actual execution of an arbitrary iOS IPA still requires a LiveContainer-style runtime.")
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
