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

    // SideInstaller must register this scheme in its own Info.plist.
    private let sideInstallerURL = URL(string: "sideinstaller://")!

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack {
                    Text("ESign")
                        .font(.title2.bold())
                    Spacer()
                    Button("Open SideInstaller") {
                        openSideInstaller()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.top)

                Text("Open the installed SideInstaller app directly.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                if !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .navigationTitle("Dual IPA")
        }
        .preferredColorScheme(.dark)
    }

    private func openSideInstaller() {
        UIApplication.shared.open(sideInstallerURL, options: [:]) { success in
            if !success {
                message = "SideInstaller cannot be opened because the installed app does not currently register the sideinstaller:// URL scheme."
            }
        }
    }
}
