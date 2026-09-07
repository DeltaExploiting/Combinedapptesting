import SwiftUI
import UniformTypeIdentifiers
import UIKit
import AuthenticationServices
import Security

@main struct DualIPAWrapperApp: App { var body: some Scene { WindowGroup { ContentView() } } }
struct GuestApp: Identifiable, Codable, Hashable { let id: UUID; let fileName: String; let displayName: String; let version: String; let importedAt: Date; let storedFileName: String }
struct EnterpriseCertificate: Identifiable, Hashable { let id=UUID(); let name:String }
let enterpriseCertificates=["Aramco Services Company","CENTRAL POWER INFORMATION TECHNOLOGY COMPANY","China Telecom Corporation Limited","HSBC Bank plc","Jiangsu Simcere Pharmaceutical Co. Ltd","Moving Increasingly Interconnected Technology Co. Ltd","VIETNAM-NEWPV"].map(EnterpriseCertificate.init(name:))

struct AppleSignInButton:UIViewRepresentable{
 let onCompletion:(Result<ASAuthorizationAppleIDCredential,Error>)->Void
 func makeCoordinator()->Coordinator{Coordinator(self)}
 func makeUIView(context:Context)->ASAuthorizationAppleIDButton{let b=ASAuthorizationAppleIDButton(type:.signIn,style:.white);b.cornerRadius=12;b.addTarget(context.coordinator,action:#selector(Coordinator.go),for:.touchUpInside);return b}
 func updateUIView(_ uiView:ASAuthorizationAppleIDButton,context:Context){}
 final class Coordinator:NSObject,ASAuthorizationControllerDelegate,ASAuthorizationControllerPresentationContextProviding{let p:AppleSignInButton;var c:ASAuthorizationController?;init(_ p:AppleSignInButton){self.p=p};@objc func go(){let r=ASAuthorizationAppleIDProvider().createRequest();r.requestedScopes=[.fullName,.email];let c=ASAuthorizationController(authorizationRequests:[r]);c.delegate=self;c.presentationContextProvider=self;self.c=c;c.performRequests()};func authorizationController(controller:ASAuthorizationController,didCompleteWithAuthorization a:ASAuthorization){c=nil;DispatchQueue.main.async{if let x=a.credential as? ASAuthorizationAppleIDCredential{self.p.onCompletion(.success(x))}}};func authorizationController(controller:ASAuthorizationController,didCompleteWithError e:Error){c=nil;DispatchQueue.main.async{self.p.onCompletion(.failure(e))}};func presentationAnchor(for controller:ASAuthorizationController)->ASPresentationAnchor{let s=UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene};let w=s.first?.windows.first(where:{$0.isKeyWindow});return w ?? ASPresentationAnchor()}}
}

struct Picker:UIViewControllerRepresentable{let exts:Set<String>;let picked:([URL])->Void;let cancel:()->Void;func makeCoordinator()->C{C(self)};func makeUIViewController(context:Context)->UIDocumentPickerViewController{let p=UIDocumentPickerViewController(documentTypes:[UTType.item.identifier],in:.import);p.delegate=context.coordinator;return p};func updateUIViewController(_ u:UIDocumentPickerViewController,context:Context){};final class C:NSObject,UIDocumentPickerDelegate{let p:Picker;init(_ p:Picker){self.p=p};func documentPicker(_ c:UIDocumentPickerViewController,didPickDocumentsAt u:[URL]){p.picked(u.filter{p.exts.contains($0.pathExtension.lowercased())})};func documentPickerWasCancelled(_ c:UIDocumentPickerViewController){p.cancel()}}}
struct IPAPicker:UIViewControllerRepresentable{let picked:([URL])->Void;let cancel:()->Void;func makeCoordinator()->C{C(self)};func makeUIViewController(context:Context)->UIDocumentPickerViewController{let p=UIDocumentPickerViewController(documentTypes:[UTType.item.identifier],in:.import);p.allowsMultipleSelection=true;p.delegate=context.coordinator;return p};func updateUIViewController(_ u:UIDocumentPickerViewController,context:Context){};final class C:NSObject,UIDocumentPickerDelegate{let p:IPAPicker;init(_ p:IPAPicker){self.p=p};func documentPicker(_ c:UIDocumentPickerViewController,didPickDocumentsAt u:[URL]){p.picked(u)};func documentPickerWasCancelled(_ c:UIDocumentPickerViewController){p.cancel()}}}

struct Certs:View{@Binding var selected:Set<String>;@Environment(\.dismiss)var dismiss;var body:some View{NavigationStack{List{Button(selected.count==enterpriseCertificates.count ? "Deselect All":"Select All"){selected=selected.count==enterpriseCertificates.count ? [] : Set(enterpriseCertificates.map{$0.name})};Section("Enterprise Certificates"){ForEach(enterpriseCertificates){x in Button{if selected.contains(x.name){selected.remove(x.name)}else{selected.insert(x.name)}}label:{Label(x.name,systemImage:selected.contains(x.name) ? "checkmark.circle.fill":"circle")}}};Text("Use only certificates you are authorized to use.").font(.footnote).foregroundStyle(.secondary)}.navigationTitle("Certificates").toolbar{Button("Done"){dismiss()}}}}}

final class KC{static let s=KC();let service="DualIPA.P12";func set(_ v:String){let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"password"];SecItemDelete(q as CFDictionary);var n=q;n[kSecValueData as String]=Data(v.utf8);SecItemAdd(n as CFDictionary,nil)};func get()->String{let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"password",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne];var r:AnyObject?;guard SecItemCopyMatching(q as CFDictionary,&r)==errSecSuccess,let d=r as? Data else{return ""};return String(data:d,encoding:.utf8) ?? ""}}

struct SigningSettings:View{@AppStorage("signingURL")var url="https://flarestore.app/api/sign";@AppStorage("p12Name")var p12Name="";@AppStorage("provName")var provName="";@State var pass="";@State var p12=false;@State var prov=false;@Environment(\.dismiss)var dismiss;let dir=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("DualIPA/SigningAssets",isDirectory:true);var body:some View{NavigationStack{Form{Section("FlareStore Signing API"){TextField("API URL",text:$url).keyboardType(.URL).textInputAutocapitalization(.never);Text("Uses FlareStore's documented POST /api/sign endpoint.").font(.footnote).foregroundStyle(.secondary)};Section("Authorized signing assets"){Button("Import P12 \(p12Name.isEmpty ? "":"✓")"){p12=true};Button("Import mobileprovision \(provName.isEmpty ? "":"✓")"){prov=true};SecureField("P12 password (optional)",text:$pass)};Text("The P12/profile are uploaded only when you explicitly press Sign & Launch.").font(.footnote).foregroundStyle(.secondary)}.navigationTitle("Signing Service").toolbar{Button("Done"){KC.s.set(pass);dismiss()}}.sheet(isPresented:$p12){Picker(exts:["p12","pfx"],picked:{u in p12=false;save(u.first,to:"signing.p12");p12Name=u.first?.lastPathComponent ?? ""},cancel:{p12=false})}.sheet(isPresented:$prov){Picker(exts:["mobileprovision"],picked:{u in prov=false;save(u.first,to:"signing.mobileprovision");provName=u.first?.lastPathComponent ?? ""},cancel:{prov=false})}.onAppear{pass=KC.s.get()}}}
func save(_ u:URL?,to name:String){guard let u else{return};try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);let d=dir.appendingPathComponent(name);try? FileManager.default.removeItem(at:d);let a=u.startAccessingSecurityScopedResource();defer{if a{u.stopAccessingSecurityScopedResource()}};try? FileManager.default.copyItem(at:u,to:d)}}

struct ContentView:View{@AppStorage("appleSignedIn")var apple=false;@AppStorage("enterpriseMode")var enterprise=false;@AppStorage("signingURL")var signingURL="https://flarestore.app/api/sign";@State var apps=[GuestApp]();@State var imp=false;@State var certs=false;@State var settings=false;@State var selected:Set<String>=[];@State var app:GuestApp?;@State var msg="";@State var signing=false;let dir=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("DualIPA",isDirectory:true)
 var body:some View{Group{if apple || enterprise{library}else{login}}.preferredColorScheme(.dark).task{load()}}
 var login:some View{VStack(spacing:20){Spacer();Image(systemName:"square.stack.3d.up.fill").font(.system(size:64));Text("Dual IPA").font(.largeTitle.bold());AppleSignInButton{r in if case .success=r{apple=true;enterprise=false}else{msg="Apple sign-in failed."}}.frame(height:52).padding();Button("Use Enterprise Certificates"){enterprise=true;apple=false}.buttonStyle(.borderedProminent);Spacer()}.alert("Dual IPA",isPresented:Binding(get:{!msg.isEmpty},set:{if !$0{msg=""}})){Button("OK"){} }message:{Text(msg)}}
 var library:some View{NavigationStack{Group{if apps.isEmpty{ContentUnavailableView("No Apps",systemImage:"square.stack.3d.up",description:Text("Import an IPA to begin."))}else{List(apps){x in Button{xSelected(x)}label:{HStack{Image(systemName:"app.fill");Text(x.displayName);Spacer();Text("Launch").foregroundStyle(.tint)}}.buttonStyle(.plain)}.onDelete{idx in apps.remove(atOffsets:idx);save()}}}.navigationTitle("Dual IPA").toolbar{ToolbarItemGroup(placement:.topBarTrailing){Button{imp=true}label:{Image(systemName:"plus")};if enterprise{Button{certs=true}label:{Label("Certificates",systemImage:"checkmark.seal")};Button{settings=true}label:{Image(systemName:"server.rack")}};Button("Sign Out"){apple=false;enterprise=false}}}.sheet(isPresented:$imp){IPAPicker(picked:{u in imp=false;importIPAs(u)},cancel:{imp=false})}.sheet(isPresented:$certs){Certs(selected:$selected)}.sheet(isPresented:$settings){SigningSettings()}.sheet(item:$app){Launch(app:$0,enterprise:enterprise,certs:selected,url:signingURL,signing:$signing){msg=$0}}.alert("Dual IPA",isPresented:Binding(get:{!msg.isEmpty},set:{if !$0{msg=""}})){Button("OK"){} }message:{Text(msg)}}}
 func xSelected(_ x:GuestApp){app=x}
 func importIPAs(_ us:[URL]){try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);for u in us{let a=u.startAccessingSecurityScopedResource();defer{if a{u.stopAccessingSecurityScopedResource()}};guard let d=try?Data(contentsOf:u),d.count>4,d[0]==0x50,d[1]==0x4B else{continue};let id=UUID(),n="\(id).ipa";try?d.write(to:dir.appendingPathComponent(n));apps.append(GuestApp(id:id,fileName:u.lastPathComponent,displayName:u.deletingPathExtension().lastPathComponent,version:"Imported",importedAt:Date(),storedFileName:n))};save()}
 func save(){try?FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try?JSONEncoder().encode(apps).write(to:dir.appendingPathComponent("apps.json"))}
 func load(){guard let d=try?Data(contentsOf:dir.appendingPathComponent("apps.json")),let x=try?JSONDecoder().decode([GuestApp].self,from:d)else{return};apps=x}}

struct Launch: View {
    let app: GuestApp
    let enterprise: Bool
    let certs: Set<String>
    let url: String
    @Binding var signing: Bool
    let message: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    private var base: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DualIPA", isDirectory: true) }
    private var ipa: URL { base.appendingPathComponent(app.storedFileName) }
    private var assets: URL { base.appendingPathComponent("SigningAssets", isDirectory: true) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "app.fill").font(.system(size: 64))
                Text(app.displayName).font(.title.bold())
                if enterprise {
                    Text(certs.count == 1 ? "Certificate selected" : "Select exactly one certificate").foregroundStyle(certs.count == 1 ? .secondary : .orange)
                    Button { sign() } label: { Label(signing ? "Signing…" : "Sign & Launch", systemImage: "signature") }.buttonStyle(.borderedProminent).disabled(signing)
                }
                Spacer()
            }.padding().navigationTitle("Launch").toolbar { Button("Done") { dismiss() } }
        }
    }
    private func sign() {
        guard certs.count == 1 else { message("Select exactly one authorized certificate."); return }
        let p12 = assets.appendingPathComponent("signing.p12")
        let provision = assets.appendingPathComponent("signing.mobileprovision")
        guard FileManager.default.fileExists(atPath: p12.path), FileManager.default.fileExists(atPath: provision.path) else { message("Import your authorized P12 and mobileprovision in Signing Service settings first."); return }
        guard let ipaData = try? Data(contentsOf: ipa), let p12Data = try? Data(contentsOf: p12), let provisionData = try? Data(contentsOf: provision), let endpoint = URL(string: url), endpoint.scheme == "https" else { message("Signing configuration is invalid."); return }
        signing = true
        let boundary = "B-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint); request.httpMethod = "POST"; request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data(); func append(_ value: String) { body.append(Data(value.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"ipa\"; filename=\"app.ipa\"\r\nContent-Type: application/octet-stream\r\n\r\n"); body.append(ipaData)
        append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"p12\"; filename=\"signing.p12\"\r\nContent-Type: application/x-pkcs12\r\n\r\n"); body.append(p12Data)
        append("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"provision\"; filename=\"signing.mobileprovision\"\r\nContent-Type: application/octet-stream\r\n\r\n"); body.append(provisionData); append("\r\n")
        let password = KC.s.get(); if !password.isEmpty { append("--\(boundary)\r\nContent-Disposition: form-data; name=\"p12_password\"\r\n\r\n\(password)\r\n") }
        append("--\(boundary)--\r\n"); request.httpBody = body
        URLSession.shared.dataTask(with: request) { data, response, error in DispatchQueue.main.async {
            signing = false
            if let error { message("Signing failed: \(error.localizedDescription)"); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else { message("Signing service returned an error."); return }
            if let result = try? JSONDecoder().decode(SigningResult.self, from: data), let path = result.installURL { let installURL = URL(string: path.hasPrefix("http") ? path : "https://flarestore.app\(path)")!; UIApplication.shared.open(installURL); message("Signing finished. Installation page opened."); return }
            if data.count > 4, data[0] == 0x50, data[1] == 0x4B, data[2] == 0x03, data[3] == 0x04 { let output = assets.appendingPathComponent("signed-\(UUID().uuidString).ipa"); do { try data.write(to: output, options: .atomic); message("Signed IPA received and saved in the app.") } catch { message("Signed IPA received but could not be saved: \(error.localizedDescription)") }; return }
            message("Signing service returned an unexpected response.")
        }}.resume()
    }
    struct SigningResult: Decodable { let installURL: String?; enum CodingKeys: String, CodingKey { case installURL = "install_url" } }
}
