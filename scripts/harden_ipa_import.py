from pathlib import Path
import re

path = Path("DualIPAWrapper/ContentView.swift")
source = path.read_text()

old_picker = 'UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item])'
new_picker = 'UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data], asCopy: true)'
if old_picker in source:
    source = source.replace(old_picker, new_picker, 1)
else:
    if 'UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data], asCopy: true)' not in source:
        raise SystemExit("IPA picker implementation was not found")

old_callback = '''        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.picked(urls)
        }'''
new_callback = '''        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            let selected = urls
            DispatchQueue.main.async {
                self.parent.picked(selected)
            }
        }'''
if old_callback in source:
    source = source.replace(old_callback, new_callback, 1)

pattern = r'''    private func importIPAs\(_ urls: \[URL\]\) \{.*?\n    \}\n\n    private func saveApps\(\)'''
replacement = '''    private func importIPAs(_ urls: [URL]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var importedCount = 0

        for sourceURL in urls {
            let scoped = sourceURL.startAccessingSecurityScopedResource()
            defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("IPA-" + UUID().uuidString + ".ipa")
            var copied = false
            var coordinationError: NSError?

            NSFileCoordinator().coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { coordinatedURL in
                do {
                    try FileManager.default.copyItem(at: coordinatedURL, to: temporaryURL)
                    copied = true
                } catch {
                    copied = false
                }
            }

            guard copied,
                  let data = try? Data(contentsOf: temporaryURL),
                  data.count >= 4,
                  data[0] == 0x50,
                  data[1] == 0x4B,
                  data[2] == 0x03 || data[2] == 0x05 || data[2] == 0x07,
                  data[3] == 0x04 || data[3] == 0x06 || data[3] == 0x08 else {
                try? FileManager.default.removeItem(at: temporaryURL)
                continue
            }

            let id = UUID()
            let stored = "\\(id).ipa"
            let destination = directory.appendingPathComponent(stored)

            do {
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                let displayName = sourceURL.deletingPathExtension().lastPathComponent
                apps.append(GuestApp(
                    id: id,
                    fileName: sourceURL.lastPathComponent,
                    displayName: displayName.isEmpty ? "Imported IPA" : displayName,
                    version: "Imported",
                    importedAt: Date(),
                    storedFileName: stored
                ))
                importedCount += 1
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        saveApps()
        if importedCount == 0 {
            message = "Could not import the selected file. Select a valid .ipa file from Files and try again."
        }
    }

    private func saveApps()'''

source, count = re.subn(pattern, replacement, source, count=1, flags=re.S)
if count != 1:
    raise SystemExit("importIPAs function was not found")

path.write_text(source)
print("IPA import implementation patched successfully")
