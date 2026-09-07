import SwiftUI
import UIKit

@main
struct DualIPAWrapperApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var message = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack {
                    Text("ESign")
                        .font(.title2.bold())
                    Spacer()
                    Button("Switch to SideInstaller") {
                        switchToSideInstaller()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.top)

                Text("ESign and SideInstaller are bundled with this app.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    exportIPA(named: "SideInstaller")
                } label: {
                    Label("Open SideInstaller IPA", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)

                Spacer()

                if !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .navigationTitle("Dual IPA")
        }
        .preferredColorScheme(.dark)
    }

    private func switchToSideInstaller() {
        message = "SideInstaller is bundled in this app. iOS does not allow an app to silently install another IPA."
        exportIPA(named: "SideInstaller")
    }

    private func exportIPA(named name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "ipa") else {
            message = "SideInstaller.ipa was not bundled."
            return
        }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        root.present(controller, animated: true)
    }
}
