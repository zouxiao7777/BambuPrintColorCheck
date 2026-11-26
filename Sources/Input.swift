import AppKit

let fm=FileManager.default
func entries(_ dir:URL)->[URL]{(try? fm.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil)) ?? []}
func mtime(_ url:URL)->Date{(try? url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast}
func textFile(_ u:URL)->String?{try? String(contentsOf:u,encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)}
func run(_ exe:String,_ args:[String],to file:URL?=nil)throws->Data{
    let task=Process(),out=Pipe(),err=Pipe()
    task.executableURL=URL(fileURLWithPath:exe);task.arguments=args;task.standardError=err
    var handle:FileHandle?
    if let f=file{fm.createFile(atPath:f.path,contents:nil);handle=try FileHandle(forWritingTo:f);task.standardOutput=handle}else{task.standardOutput=out}
    defer{try? handle?.close()}
    try task.run();let result=file==nil ? out.fileHandleForReading.readDataToEndOfFile():Data()
    let error=err.fileHandleForReading.readDataToEndOfFile();task.waitUntilExit()
    guard task.terminationStatus == 0 else {
        let detail = String(decoding: error.prefix(500), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let helperErrors = [
            "toolpath_limit": UIString("外表面路径超过此版本的显示容量", "The exterior toolpaths exceed the preview capacity."),
            "no_surface": UIString("未找到带特征标记的模型外表面路径", "No tagged exterior toolpaths were found."),
            "cannot_open": UIString("切片文件无法打开", "The slice file could not be opened."),
            "read_interrupted": UIString("切片读取中断", "Reading the slice was interrupted.")
        ]
        if let known = helperErrors[detail] { throw PreviewError(known) }
        throw PreviewError(detail.isEmpty ? UIString("读取失败", "Read failed.") : UIString(verbatim: detail))
    }
    return result
}
struct Input {
    let url:URL,label:UIString,pid:Int32?,origin:URL?,image:URL?,member:String?,imageMember:String?
    var id:String {url.path+"|"+(member ?? imageMember ?? "")}
}
struct Header{
    var colors=[String](), slots=[Int](), time="",layers="",height="",grams:Double?
    init(_ u:URL)throws{
        let f=try FileHandle(forReadingFrom:u);defer{try? f.close()}
        let text=String(decoding:try f.read(upToCount:1024*1024) ?? Data(),as:UTF8.self)
        for l in text.components(separatedBy:"\n"){
            func rest(_ p:String)->String?{l.hasPrefix(p) ? String(l.dropFirst(p.count)).trimmingCharacters(in:.whitespacesAndNewlines):nil}
            if let v=rest("; filament_colour ="){colors=v.split(separator:";").map{String($0.prefix(7)).uppercased()}}
            if let v=rest("; filament:"){slots=v.split(separator:",").compactMap{Int($0.trimmingCharacters(in:.whitespaces)).map{$0-1}}}
            if let v=rest("; total layer number:"){layers=v}
            if let v=rest("; total filament weight [g] :"){
                let amounts=v.split(separator:",").compactMap{Double($0.trimmingCharacters(in:.whitespaces))};if !amounts.isEmpty{grams=amounts.reduce(0,+)}
            }
            if let v=rest("; max_z_height:"){height=v}
            if l.hasPrefix("; model printing time:"),let r=l.range(of:"total estimated time: "){time=String(l[r.upperBound...]).trimmingCharacters(in:.whitespacesAndNewlines)}
            if l.hasPrefix("; CONFIG_BLOCK_END"){break}
        }
    }
    var detail: UIString {
        let zh = [layers.isEmpty ? "" : "\(layers) 层", height.isEmpty ? "" : "高 \(height) mm", time]
        let en = [layers.isEmpty ? "" : "\(layers) layers", height.isEmpty ? "" : "\(height) mm tall", time]
        return UIString(zh.filter{!$0.isEmpty}.joined(separator:"  ·  "), en.filter{!$0.isEmpty}.joined(separator:"  ·  "))
    }
}
func liveInputs()->[Input] {
    let live=Set(NSRunningApplication.runningApplications(withBundleIdentifier:"com.bambulab.bambu-studio").map{$0.processIdentifier})
    let root=fm.temporaryDirectory.appendingPathComponent("bamboo_model")
    var result=[Input]()
    for date in entries(root){for dir in entries(date){
        guard let pid=Int32(textFile(dir.appendingPathComponent("lock.txt")) ?? ""),live.contains(pid) else{continue}
        let d=dir.appendingPathComponent("Metadata"),files=entries(d)
        let codes=files.filter{$0.lastPathComponent.hasPrefix(".\(pid).") && $0.pathExtension=="gcode"}
        let pics=files.filter{$0.lastPathComponent.range(of:"^plate_[0-9]+[.]png$",options:.regularExpression) != nil}
        let origin=textFile(dir.appendingPathComponent("origin.txt")).map{URL(fileURLWithPath:$0)}
        let name=origin.map{UIString(verbatim:$0.deletingPathExtension().lastPathComponent)} ?? UIString("未命名工程", "Untitled project")
        for u in codes{
            guard let f=try? FileHandle(forReadingFrom:u) else{continue}
            let length=(try? f.seekToEnd()) ?? 0
            try? f.seek(toOffset:length>8192 ? length-8192:0)
            let tail=String(decoding:(try? f.readToEnd()) ?? Data(),as:UTF8.self);try? f.close()
            guard tail.contains("; EXECUTABLE_BLOCK_END") || tail.contains("; filament used [mm]") else{continue}
            let fmt=DateFormatter();fmt.dateFormat="MM-dd HH:mm"
            let pic=(codes.count==1 && pics.count==1) ? pics[0]:nil
            let label=name.appending(UIString(verbatim:fmt.string(from:mtime(u))),separator:" · ")
            result.append(Input(url:u,label:label,pid:pid,origin:origin,image:pic,member:nil,imageMember:nil))
        }
    }}
    return result.sorted{mtime($0.url)>mtime($1.url)}
}
func imported(_ url:URL)throws->[Input] {
    if url.pathExtension.lowercased()=="gcode"{return [Input(url:url,label:UIString(verbatim:url.lastPathComponent),pid:nil,origin:nil,image:nil,member:nil,imageMember:nil)]}
    guard url.pathExtension.lowercased()=="3mf" else{throw PreviewError("请选择 .gcode、.gcode.3mf 或 .3mf。", "Choose a .gcode, .gcode.3mf or .3mf file.")}
    let listing=String(decoding:try run("/usr/bin/unzip",["-l",url.path]),as:UTF8.self)
    var codes=[Int:String](),pictures=[Int:String]()
    for l in listing.components(separatedBy:"\n"){
        let fields=l.split(whereSeparator:{$0.isWhitespace});guard fields.count==4,let n=UInt64(fields[0]) else{continue}
        let path=String(fields[3]);guard path.range(of:"^Metadata/plate_[1-9][0-9]*[.](gcode|png)$",options:.regularExpression) != nil else{continue}
        guard let i=Int(path.dropFirst(15).prefix(while:{$0.isNumber})) else{continue}
        if path.hasSuffix(".png"),n<32000000{pictures[i]=path}
        if path.hasSuffix(".gcode"),n<1500000000{codes[i]=path}
    }
    let nums=Set(codes.keys).union(pictures.keys).sorted()
    guard !nums.isEmpty else{throw PreviewError("工程中没有盘面图或已切片的打印盘。", "The project contains no plate image or sliced plate.")}
    return nums.map{i in Input(url:url,label:UIString(url.lastPathComponent+" · 第 \(i) 盘",url.lastPathComponent+" · Plate \(i)"),pid:nil,origin:url,image:nil,member:codes[i],imageMember:pictures[i])}
}
