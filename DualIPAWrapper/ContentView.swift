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
}

struct ContentView: View {
    @State private var apps: [GuestApp] = []
    @State private var showingImporter = false
    @State private var selectedApp: GuestApp?
    @State private var message = ""

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
                                    }
                                    Spacer()
                                    Text("Launch")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tint)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { apps.remove(atOffsets: $0); saveApps() }
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
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
                          allowsMultipleSelection: true) { result in
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
        case .failure(let error): message = error.localizedDescription
        case .success(let urls):
            var imported = 0
            for url in urls where url.pathExtension.lowercased() == "ipa" {
                let app = GuestApp(id: UUID(), fileName: url.lastPathComponent,
                                   displayName: url.deletingPathExtension().lastPathComponent,
                                   version: "Imported", importedAt: Date())
                if !apps.contains(where: { $0.fileName == app.fileName }) {
                    apps.append(app); imported += 1
                }
            }
            saveApps()
            if imported == 0 { message = "No new IPA files were imported." }
        }
    }

    private var storageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DualIPA", isDirectory: true)
    }

    private func saveApps() {
        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(apps)
            try data.write(to: storageURL.appendingPathComponent("apps.json"), options: .atomic)
        } catch { message = "Could not save the app library." }
    }

    private func loadApps() {
        guard let data = try? Data(contentsOf: storageURL.appendingPathComponent("apps.json")),
              let saved = try? JSONDecoder().decode([GuestApp].self, from: data) else { return }
        apps = saved
    }
}

struct GuestContainerView: View {
    let app: GuestApp
    @Environment(\.dismiss) private var dismiss

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

                Text("The IPA is registered in the Dual IPA library. A normal iOS app cannot execute an arbitrary IPA merely by embedding it; a LiveContainer-style runtime is required for actual guest execution.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("Launch")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
