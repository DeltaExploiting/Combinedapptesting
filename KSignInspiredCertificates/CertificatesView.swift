import SwiftUI

struct CertificateItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let subtitle: String
}

struct CertificatesView: View {
    private let certificates = [
        CertificateItem(name: "Moving Increasingly Interconnected Technology Co., Ltd.", subtitle: "Certificate"),
        CertificateItem(name: "China Telecom Corporation Limited", subtitle: "Certificate"),
        CertificateItem(name: "HSBC Bank Plc", subtitle: "Certificate"),
        CertificateItem(name: "CENTRAL POWER INFORMATION TECHNOLOGY COMPANY", subtitle: "Certificate")
    ]
    @State private var selectedCertificate: UUID?
    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.055, blue: 0.07).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack { Text("Certificates").font(.title2.bold()); Spacer(); Button(action: {}) { Image(systemName: "plus") } }
                    .foregroundStyle(.white).padding(.horizontal, 20).padding(.vertical, 16)
                ScrollView { LazyVStack(spacing: 12) { ForEach(certificates) { cert in
                    Button { withAnimation { selectedCertificate = cert.id } } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(selectedCertificate == cert.id ? .green : .gray)
                            VStack(alignment: .leading, spacing: 5) { Text(cert.name).foregroundStyle(.white).multilineTextAlignment(.leading); Text(cert.subtitle).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Image(systemName: selectedCertificate == cert.id ? "checkmark.circle.fill" : "circle").foregroundStyle(selectedCertificate == cert.id ? .green : .gray)
                        }.padding(16).background(Color.white.opacity(selectedCertificate == cert.id ? 0.12 : 0.07)).clipShape(RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                } }.padding(18) }
                HStack { Text(selectedCertificate == nil ? "No certificate selected" : "Certificate selected").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Import") {}.buttonStyle(.bordered) }
                    .padding(20)
            }
        }.preferredColorScheme(.dark)
    }
}
