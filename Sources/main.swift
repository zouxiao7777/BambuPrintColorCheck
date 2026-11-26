import AppKit
import WebKit
import ScreenCaptureKit
import UniformTypeIdentifiers
import CryptoKit

final class LocalFiles:NSObject,WKURLSchemeHandler {
    let root:URL, web:URL
    init(root:URL,web:URL){self.root=root;self.web=web}
    func webView(_ webView:WKWebView,start task:WKURLSchemeTask){
        guard let url=task.request.url,url.host=="local" else{return}
        let parts=url.pathComponents.filter{$0 != "/"}
        var f:URL?
        if parts.count==1,["index.html","app.js","viewer.js","language.js","style.css","AboutIcon.png"].contains(parts[0]){f=web.appendingPathComponent(parts[0])}
        if parts.count==3,parts[0]=="work",UUID(uuidString:parts[1]) != nil,["paths.bin","plate.png"].contains(parts[2]){f=root.appendingPathComponent(parts[1]).appendingPathComponent(parts[2])}
        guard let file=f,let data=try? Data(contentsOf:file,options:.mappedIfSafe) else{task.didFailWithError(PreviewError("预览资源无法读取", "The preview resource could not be opened."));return}
        let type=["html":"text/html","js":"application/javascript","css":"text/css","png":"image/png","bin":"application/octet-stream"][file.pathExtension]!
        task.didReceive(HTTPURLResponse(url:url,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":type,"Access-Control-Allow-Origin":"*","Cache-Control":"no-cache"])!)
        task.didReceive(data);task.didFinish()
    }
    func webView(_ webView:WKWebView,stop task:WKURLSchemeTask){}
}
final class App:NSObject,NSApplicationDelegate,WKScriptMessageHandler,NSWindowDelegate,WKNavigationDelegate {
    let root=fm.temporaryDirectory.appendingPathComponent("plate-preview-"+UUID().uuidString)
    var window:NSWindow!,web:WKWebView!
    var live=[Input](),extra=[Input](),selected:Input?,token="",header:Header?,ready=false
    var pendingURL:URL?,pendingShot:URL?,exportURL:URL?,exportFocus = -1,lastScan=false,actualOnly=false
    var autoRead=true,hadLiveWindow=false,lastImageHash:SHA256.Digest?,mapRequest=UUID()
    var watch:Timer?
    var all:[Input]{extra+live}
    func call(_ fn:String,_ data:Any){
        guard let b=try? JSONSerialization.data(withJSONObject:data,options:[.fragmentsAllowed]),let json=String(data:b,encoding:.utf8) else{return}
        web.evaluateJavaScript("void window.\(fn)(\(json))"){_,e in if let e=e{fputs(e.localizedDescription+"\n",stderr)}}
    }
    func exportError(_ reason:String){
        guard exportURL != nil else{return}
        fputs(reason+"\n",stderr);try? fm.removeItem(at:root);exit(1)
    }
    func notice(_ text:UIString){ call("notice",text.payload) }
    private let aboutMenuItem = NSMenuItem()
    private let quitMenuItem = NSMenuItem()
    @objc private func openAboutPage() {
        window.makeKeyAndOrderFront(nil)
        call("openAbout", NSNull())
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "plate", url.host == "local" { decisionHandler(.allow); return }
        if action.navigationType == .linkActivated, url.scheme == "https", url.host == "github.com" {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }
    func updateNativeLanguage() {
        let title = UIString("打印配色核对", "Print Color Check").value
        window.title = title
        let menu = NSApp.mainMenu?.items.first?.submenu
        menu?.title = title
        aboutMenuItem.title = UIString("关于打印配色核对", "About Print Color Check").value
        quitMenuItem.title = UIString("退出打印配色核对", "Quit Print Color Check").value
    }
    func applicationDidFinishLaunching(_ n:Notification){
        try? fm.createDirectory(at:root,withIntermediateDirectories:true)
        let config=WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFiles(root:root,web:Bundle.main.resourceURL!.appendingPathComponent("Web")),forURLScheme:"plate")
        let info = Bundle.main.infoDictionary ?? [:]
        let appInfo = ["version": info["CFBundleShortVersionString"] as? String ?? "",
                       "build": info["CFBundleVersion"] as? String ?? ""]
        let json = String(decoding: try! JSONEncoder().encode(appInfo), as: UTF8.self)
        let startup = "window.initialLanguage = '\(InterfaceLanguage.current.rawValue)'; window.appInfo = \(json);"
        config.userContentController.addUserScript(WKUserScript(source:startup,injectionTime:.atDocumentStart,forMainFrameOnly:true))
        config.userContentController.add(self,name:"host")
        web=WKWebView(frame:.zero,configuration:config)
        web.navigationDelegate=self
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1050,height:810),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        window.minSize=NSSize(width:660,height:500);window.contentView=web;window.delegate=self;window.center()
        let menu=NSMenu(),appMenu=NSMenu()
        aboutMenuItem.target=self;aboutMenuItem.action=#selector(openAboutPage)
        appMenu.addItem(aboutMenuItem)
        appMenu.addItem(.separator())
        quitMenuItem.action=#selector(NSApplication.terminate(_:));quitMenuItem.keyEquivalent="q"
        appMenu.addItem(quitMenuItem)
        let item=NSMenuItem();menu.addItem(item);item.submenu=appMenu;NSApp.mainMenu=menu;updateNativeLanguage()
        let args=Array(CommandLine.arguments.dropFirst())
        if let i=args.firstIndex(of:"--export"),i+1<args.count{exportURL=URL(fileURLWithPath:args[i+1])}
        actualOnly=args.contains("--actual-only")
        if let i=args.firstIndex(of:"--highlight"),i+1<args.count{exportFocus=(Int(args[i+1]) ?? 0)-1}
        if let i=args.firstIndex(of:"--snapshot"),i+1<args.count{pendingShot=URL(fileURLWithPath:args[i+1])}
        if let i=args.firstIndex(of:"--project"),i+1<args.count{pendingURL=URL(fileURLWithPath:args[i+1])}
        watch=Timer.scheduledTimer(withTimeInterval:4,repeats:true){[weak self] _ in
            guard let self=self,self.autoRead,self.exportURL==nil,self.header != nil,self.selected?.pid != nil,CGPreflightScreenCaptureAccess() else{return}
            Task{@MainActor in self.capture(quiet:true)}
        }
        web.load(URLRequest(url:URL(string:"plate://local/index.html")!))
        presentWindow()
        if exportURL == nil {
            NSApp.servicesProvider = self
            NSUpdateDynamicServices()
        }
    }
    private func presentWindow() {
        NSApp.unhide(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc(showPrintColorCheck:userData:error:)
    func showPrintColorCheck(_ pasteboard: NSPasteboard, userData: String?,
                             error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        if ready { call("closeAbout", NSNull()) }
        presentWindow()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window != nil { presentWindow() }
        return false
    }
    func windowWillClose(_ notification:Notification){NSApp.terminate(nil)}
    func applicationWillTerminate(_ n:Notification){try? fm.removeItem(at:root)}
    func application(_ application:NSApplication,open urls:[URL]){guard let u=urls.first else{return};if ready{openFile(u)}else{pendingURL=u}}
    func list(_ id:String){call("setSources",["list":all.map{["id":$0.id,"label":$0.label.payload]},"id":id])}
    func refresh(keep:Bool){
        live=liveInputs()
        let next=(keep ? all.first{$0.id==selected?.id}:nil) ?? all.first
        list(next?.id ?? "")
        if let next=next{load(next)}else{selected=nil;token=UUID().uuidString;call("loading",token);call("loaded",["token":token])}
    }
    func openFile(_ u:URL){
        let same=live.filter{$0.origin?.standardizedFileURL==u.standardizedFileURL}
        if same.count==1 {list(same[0].id);load(same[0]);return}
        do{let added=try imported(u);extra.removeAll{$0.url==u};extra=added+extra;list(added[0].id);load(added[0])}catch{notice(UIString(error:error))}
    }
    func panel(_ screenshot:Bool){
        let p=NSOpenPanel();p.allowedContentTypes=screenshot ? [.png,.jpeg,.tiff]:["3mf","gcode"].compactMap{UTType(filenameExtension:$0)};p.allowsMultipleSelection=false
        p.title = screenshot ? UIString("导入发送窗口截图", "Import Print Window Screenshot").value : UIString("打开切片或工程", "Open Slice or Project").value
        p.prompt = UIString("打开", "Open").value
        p.beginSheetModal(for:window){answer in guard answer == .OK,let url=p.url else{return};if screenshot{self.autoRead=false;self.mapImage(url,source:"import",date:self.date(mtime(url)))}else{self.openFile(url)}}
    }
    func date(_ d:Date)->String{let f=DateFormatter();f.dateFormat="MM-dd HH:mm:ss";return f.string(from:d)}
    func load(_ item:Input){
        let previous=token
        lastImageHash=nil;hadLiveWindow=false;autoRead=true;mapRequest=UUID();selected=item;token=UUID().uuidString;header=nil;let k=token
        let dir=root.appendingPathComponent(k),base="plate://local/work/"+k+"/"
        call("loading",k)
        let helper=Bundle.main.url(forAuxiliaryExecutable:"plate-paths")!
        DispatchQueue.global(qos:.userInitiated).async{
            var data:[String:Any]=["token":k,"detail":item.label.payload];var h:Header?
            do{
                try fm.createDirectory(at:dir,withIntermediateDirectories:true)
                let img=dir.appendingPathComponent("plate.png")
                if let p=item.image, (try? fm.copyItem(at:p,to:img)) != nil{data["plate"]=base+"plate.png"}
                if let member=item.imageMember{_ = try run("/usr/bin/unzip",["-p",item.url.path,member],to:img);data["plate"]=base+"plate.png"}
                var u=item.url
                if let member=item.member{u=dir.appendingPathComponent("plate.gcode");_ = try run("/usr/bin/unzip",["-p",item.url.path,member],to:u)}
                guard u.pathExtension=="gcode" else{throw PreviewError("此工程没有已切片路径。在 Studio 切片后刷新，或打开导出的 .gcode.3mf。", "This project has no sliced toolpaths. Slice it in Studio and refresh, or open an exported .gcode.3mf.")}
                let before=mtime(u);h=try Header(u)
                _ = try run(helper.path,[u.path,dir.appendingPathComponent("paths.bin").path])
                guard before==mtime(u) else{throw PreviewError("切片正在更新，请完成后刷新。", "The slice is being updated. Refresh once slicing is complete.")}
                data["paths"]=base+"paths.bin";data["colors"]=h!.colors;data["detail"]=item.label.appending(h!.detail,separator:"  ·  ").payload
            }catch{data["error"]=UIString(error:error).payload}
            DispatchQueue.main.async{
                guard self.token==k else{try? fm.removeItem(at:dir);return}
                self.header=h;self.call("loaded",data)
                if !previous.isEmpty{try? fm.removeItem(at:self.root.appendingPathComponent(previous))}
            }
        }
    }
    func mapImage(_ u:URL,source:String,date:String){
        guard let h=header else{notice(UIString("请先选择已完成切片的工程。", "Select a completed slice first."));return}
        let k=token,request=UUID();mapRequest=request;call("mapPending",UIString("正在核对耗材卡…", "Checking filament cards…").payload)
        DispatchQueue.global(qos:.userInitiated).async{
            do{
                defer{if u.deletingLastPathComponent()==self.root,u.lastPathComponent.hasPrefix("window-"){try? fm.removeItem(at:u)}}
                let cards=try MappingReader(u).read(colors:h.colors,slots:h.slots,grams:h.grams)
                DispatchQueue.main.async{if k==self.token && self.mapRequest==request{self.call("mapped",["token":k,"cards":cards,"stamp":["source":source,"date":date]]);if self.exportURL != nil {self.call("saveImage",["focus":self.exportFocus,"single":self.actualOnly])}}}
            }catch{DispatchQueue.main.async{if k==self.token && self.mapRequest==request{self.call("mapFailed",UIString(error:error).payload);self.exportError(error.localizedDescription)}}}
        }
    }
    @MainActor func capture(quiet:Bool=false){
        guard let pid=selected?.pid else{notice(UIString("打开运行中工程的切片后可读取窗口，也可导入此盘的发送窗口截图。", "Select a slice from an open Studio project to read its window, or import a screenshot for this plate."));return}
        guard !lastScan else{return};lastScan=true
        let k=token
        if !quiet{lastImageHash=nil;call("mapPending",UIString("正在读取 Bambu Studio 发送窗口…", "Reading the Bambu Studio print window…").payload)}
        Task{
            defer{lastScan=false}
            do{
                let list=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
                guard !list.displays.isEmpty else{throw PreviewError("macOS 当前没有可捕获的显示器，请使用发送窗口截图。", "macOS has no display available for capture. Import a screenshot of the Send Print Job window.")}
                let wins=list.windows.filter{w in
                    guard w.owningApplication?.processID==pid else{return false}
                    let s=w.title?.lowercased() ?? ""
                    return s.contains("发送打印任务") || s.contains("send print job") || s.contains("send print task")
                }
                if wins.isEmpty && quiet && exportURL==nil{
                    if hadLiveWindow{hadLiveWindow=false;lastImageHash=nil;mapRequest=UUID();call("mapFailed",UIString("发送窗口已关闭。重新打开后会自动读取本次槽位配色。", "The print window is closed. Reopen it to read the current slot colors automatically.").payload)}
                    return
                }
                guard wins.count==1 else{throw PreviewError("请在所选工程点“打印单盘”，保持发送窗口打开并显示全部耗材卡，再点“读取 AMS”。也可导入截图。", "In the selected project, click Print Plate. Keep all filament cards visible in the Send Print Job window, then click Read AMS. You can also import a screenshot.")}
                let filter=SCContentFilter(desktopIndependentWindow:wins[0]),c=SCStreamConfiguration()
                c.width=Int(filter.contentRect.width*CGFloat(filter.pointPixelScale));c.height=Int(filter.contentRect.height*CGFloat(filter.pointPixelScale));c.showsCursor=false
                let im=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:c)
                guard k==token && autoRead else{return}
                hadLiveWindow=true
                guard let bytes=NSBitmapImageRep(cgImage:im).representation(using:.png,properties:[:]) else{throw PreviewError("未取得窗口图像", "The window image could not be captured.")}
                let digest=SHA256.hash(data:bytes)
                if lastImageHash==digest{return};lastImageHash=digest
                let f=root.appendingPathComponent("window-"+UUID().uuidString+".png")
                try bytes.write(to:f);mapImage(f,source:"live",date:date(Date()))
            }catch{if k==token && autoRead{mapRequest=UUID();lastImageHash=nil;call("mapFailed",UIString(error:error).appending(UIString("可使用“导入截图”。","You can also import a screenshot."),separator:" ").payload);exportError(error.localizedDescription)}}
        }
    }
    func save(_ b:[String:Any]){
        guard let s=b["png"] as? String,let bytes=Data(base64Encoded:s),bytes.prefix(4)==Data([137,80,78,71]) else{return}
        if let u=exportURL{do{try bytes.write(to:u,options:.withoutOverwriting);print(u.path)}catch{exportError(error.localizedDescription)};NSApp.terminate(nil);return}
        let p=NSSavePanel();p.allowedContentTypes=[.png];p.nameFieldStringValue=UIString("打印配色核对.png","Print Color Check.png").value
        p.title=UIString("保存配色核对图","Save Color Check Image").value;p.prompt=UIString("保存","Save").value
        p.beginSheetModal(for:window){answer in if answer == .OK,let u=p.url{do{try bytes.write(to:u,options:.atomic)}catch{self.notice(UIString(error:error))}}}
    }
    func userContentController(_ c:WKUserContentController,didReceive message:WKScriptMessage){
        guard let b=message.body as? [String:Any],let name=b["name"] as? String else{return}
        if exportURL != nil {fputs(name+"\n",stderr)}
        switch name{
        case "ready":ready=true;live=liveInputs();if let u=pendingURL{pendingURL=nil;openFile(u)}else{refresh(keep:false)}
        case "failed":exportError(b["error"] as? String ?? UIString("无法载入","Could not load preview.").value)
        case "rendered":
            guard b["token"] as? String==token else{return}
            if let u=pendingShot{pendingShot=nil;autoRead=false;mapImage(u,source:"supplied",date:date(mtime(u)))}
            else if CGPreflightScreenCaptureAccess(), selected?.pid != nil {Task{@MainActor in capture(quiet:true)}}
            else{exportError(UIString("当前无法读取实时窗口，请提供 --snapshot 发送窗口截图。","The live window is unavailable. Supply a print window screenshot with --snapshot.").value)}
        case "language":
            if let raw=b["value"] as? String, let language=InterfaceLanguage(rawValue:raw) {
                UserDefaults.standard.set(language.rawValue,forKey:InterfaceLanguage.preference)
                updateNativeLanguage()
            }
        case "refresh":refresh(keep:true)
        case "open":panel(false)
        case "shot":panel(true)
        case "ams":autoRead=true;Task{@MainActor in capture()}
        case "select":if let id=b["id"] as? String,let input=all.first(where:{$0.id==id}){load(input)}
        case "fullscreen":window.toggleFullScreen(nil)
        case "save":save(b)
        default:break
        }
    }
}
let application=NSApplication.shared,delegate=App()
application.setActivationPolicy(.regular);application.delegate=delegate;application.run()
