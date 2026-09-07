import SwiftUI
import UniformTypeIdentifiers

enum AppTab: String, CaseIterable {
    case files = "Files", library = "Library", appStore = "App Store", downloads = "Downloads", settings = "Settings"
    var icon: String {
        switch self { case .files: return "folder"; case .library: return "square.grid.2x2"; case .appStore: return "bag"; case .downloads: return "arrow.down.circle"; case .settings: return "gearshape" }
    }
}

struct RootView: View {
    @State private var tab: AppTab = .files
    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .files: FilesView()
                case .library: PlaceholderView(title: "Library", icon: "square.grid.2x2", message: "Signed and imported apps will appear here.")
                case .appStore: PlaceholderView(title: "App Store", icon: "bag", message: "Add an app source to browse packages.")
                case .downloads: PlaceholderView(title: "Downloads", icon: "arrow.down.circle", message: "Downloaded files will appear here.")
                case .settings: SettingsView()
                }
            }.safeAreaInset(edge: .bottom) { Color.clear.frame(height: 70) }
            HStack {
                ForEach(AppTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        VStack(spacing: 5) { Image(systemName: item.icon); Text(item.rawValue).font(.caption2) }
                            .frame(maxWidth: .infinity).foregroundStyle(tab == item ? .white : .gray)
                    }
                }
            }.padding(.top, 12).padding(.bottom, 8).background(.ultraThinMaterial)
        }.preferredColorScheme(.dark)
    }
}

struct FilesView: View {
    @State private var showingImporter = false
    @State private var importedFiles: [String] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack { Text("Files").font(.largeTitle.bold()); Spacer(); Button { showingImporter = true } label: { Image(systemName: "plus").font(.title2) } }
                    .foregroundStyle(.white).padding()
                if importedFiles.isEmpty {
                    ContentUnavailableView("No Files", systemImage: "folder", description: Text("Import an IPA to get started."))
                } else {
                    List(importedFiles, id: \.self) { file in
                        Label(file, systemImage: "app.fill").foregroundStyle(.white)
                    }.scrollContentBackground(.hidden)
                }
                Spacer()
                Button { showingImporter = true } label: {
                    Label("Import IPA", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity).padding()
                }.buttonStyle(.borderedProminent).padding()
            }
            .background(Color(red: 0.055, green: 0.055, blue: 0.07))
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.data, .item], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    for url in urls where url.pathExtension.lowercased() == "ipa" {
                        importedFiles.append(url.lastPathComponent)
                    }
                    if urls.allSatisfy({ $0.pathExtension.lowercased() != "ipa" }) { errorMessage = "Please select an .ipa file." }
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
            .alert("Import IPA", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Signing") {
                    NavigationLink("Certificates", destination: CertificatesView())
                    NavigationLink("Provisioning Profiles", destination: PlaceholderView(title: "Provisioning Profiles", icon: "doc", message: "This section is ready for implementation."))
                    NavigationLink("Signing Options", destination: PlaceholderView(title: "Signing Options", icon: "signature", message: "This section is ready for implementation."))
                }
                Section("Appearance") {
                    NavigationLink("Theme", destination: PlaceholderView(title: "Theme", icon: "paintbrush", message: "This section is ready for implementation."))
                    NavigationLink("About", destination: PlaceholderView(title: "About", icon: "info.circle", message: "KSign-inspired unsigned IPA builder."))
                }
            }.scrollContentBackground(.hidden).background(Color(red: 0.055, green: 0.055, blue: 0.07)).navigationTitle("Settings")
        }
    }
}

struct PlaceholderView: View {
    let title: String; let icon: String; let message: String
    var body: some View {
        VStack(spacing: 18) { Image(systemName: icon).font(.system(size: 48)); Text(title).font(.title2.bold()); Text(message).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.055, green: 0.055, blue: 0.07)).foregroundStyle(.white)
    }
}
