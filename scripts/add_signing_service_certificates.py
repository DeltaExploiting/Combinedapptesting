from pathlib import Path

path = Path("DualIPAWrapper/ContentView.swift")
source = path.read_text()

if "selectedSigningCertificates" not in source:
    anchor = '    @State private var pickingProvision = false\n'
    if anchor not in source:
        raise SystemExit("SigningSettingsView state anchor not found")
    source = source.replace(
        anchor,
        anchor + '    @State private var selectedSigningCertificates: Set<String> = Set(enterpriseCertificates.map(\\.name))\n',
        1,
    )

section_marker = '                Text("The signing assets are uploaded only when you explicitly press Sign & Launch.")'
if "Section(\"Certificates\")" not in source:
    if section_marker not in source:
        raise SystemExit("Signing service certificate section anchor not found")
    section = '''                Section("Certificates") {
                    ForEach(enterpriseCertificates) { certificate in
                        Button {
                            if selectedSigningCertificates.contains(certificate.name) {
                                selectedSigningCertificates.remove(certificate.name)
                            } else {
                                selectedSigningCertificates.insert(certificate.name)
                            }
                        } label: {
                            HStack {
                                Text(certificate.name)
                                Spacer()
                                Image(systemName: selectedSigningCertificates.contains(certificate.name) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedSigningCertificates.contains(certificate.name) ? Color.accentColor : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        Button("Select All") {
                            selectedSigningCertificates = Set(enterpriseCertificates.map(\\.name))
                        }
                        Spacer()
                        Button("Deselect All") {
                            selectedSigningCertificates.removeAll()
                        }
                    }
                }

'''
    source = source.replace(section_marker, section + section_marker, 1)

path.write_text(source)
print("Signing service certificate box patched successfully")
