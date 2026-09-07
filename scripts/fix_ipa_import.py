from pathlib import Path

p = Path("DualIPAWrapper/ContentView.swift")
s = p.read_text()

old = '''        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item])
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker'''
new = '''        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker'''
if old not in s:
    raise SystemExit("IPA picker block not found")
s = s.replace(old, new, 1)

old = '''        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.picked(urls)
        }'''
new = '''        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            var localURLs: [URL] = []
            for sourceURL in urls {
                let scoped = sourceURL.startAccessingSecurityScopedResource()
                defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("IPA-" + UUID().uuidString + ".ipa")
                var copied = false
                var coordinationError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { coordinatedURL in
                    copied = (try? FileManager.default.copyItem(at: coordinatedURL, to: destination)) != nil
                }
                if copied {
                    localURLs.append(destination)
                }
            }
            DispatchQueue.main.async {
                self.parent.picked(localURLs)
            }
        }'''
if old not in s:
    raise SystemExit("IPA picker callback not found")
s = s.replace(old, new, 1)

old = '''    private func importIPAs(_ urls: [URL]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), data.count > 4,
                  data[0] == 0x50, data[1] == 0x4B else { continue }
            let id = UUID()
            let stored = "\\(id).ipa"
            try? data.write(to: directory.appendingPathComponent(stored), options: .atomic)
            apps.append(GuestApp(id: id, fileName: url.lastPathComponent, displayName: url.deletingPathExtension().lastPathComponent, version: "Imported", importedAt: Date(), storedFileName: stored))
        }
        saveApps()
    }'''
new = '''    private func importIPAs(_ urls: [URL]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var imported = 0

        for url in urls {
            guard let data = try? Data(contentsOf: url), data.count >= 4 else { continue }
            guard data[0] == 0x50, data[1] == 0x4B,
                  (data[2] == 0x03 && data[3] == 0x04) ||
                  (data[2] == 0x05 && data[3] == 0x06) ||
                  (data[2] == 0x07 && data[3] == 0x08) else { continue }

            let id = UUID()
            let stored = "\\(id).ipa"
            do {
                try data.write(to: directory.appendingPathComponent(stored), options: .atomic)
                apps.append(GuestApp(id: id, fileName: url.lastPathComponent,
                                     displayName: url.deletingPathExtension().lastPathComponent,
                                     version: "Imported", importedAt: Date(), storedFileName: stored))
                imported += 1
            } catch { }
        }
        saveApps()
        if imported == 0 {
            message = "Could not import the selected file. Select a valid .ipa file from Files."
        }
    }'''
if old not in s:
    raise SystemExit("importIPAs function not found")
s = s.replace(old, new, 1)

p.write_text(s)
print("IPA import fix applied")
