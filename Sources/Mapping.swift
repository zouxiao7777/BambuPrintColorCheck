import AppKit
import Vision
import ImageIO

struct PreviewError: LocalizedError {
    let message: UIString
    init(_ zh: String, _ en: String) { message = UIString(zh, en) }
    init(_ text: UIString) { message = text }
    var errorDescription: String? { message.value }
}
struct RGB {
    let r:Int, g:Int, b:Int
    init(_ r:Int,_ g:Int,_ b:Int){self.r=r;self.g=g;self.b=b}
    init?(_ hex:String){guard hex.count == 7,hex.first=="#",let n=Int(hex.dropFirst(),radix:16) else{return nil};self.init(n>>16,(n>>8)&255,n&255)}
    var hex:String {String(format:"#%02X%02X%02X",r,g,b)}
    func distance(_ other:RGB)->Int{max(abs(r-other.r),abs(g-other.g),abs(b-other.b))}
}
private func shape(_ bits:[[Bool]])->[Bool]? {
    let pts=bits.enumerated().flatMap{ y,row in row.indices.filter{row[$0]}.map{($0,y)} }
    guard let l=pts.map({$0.0}).min(),let r=pts.map({$0.0}).max(),let t=pts.map({$0.1}).min(),let b=pts.map({$0.1}).max(),b>t,r>l else{return nil}
    return (0..<32).flatMap{ y in (0..<24).map{ x in bits[t+((2*y+1)*(b-t+1))/64][l+((2*x+1)*(r-l+1))/48] } }
}
private let digits:[(String,[Bool])] = {
    var results=[(String,[Bool])]()
    for weight in [NSFont.Weight.medium,.semibold,.bold] {
        let font=NSFont.systemFont(ofSize:48,weight:weight) as CTFont
        for n in 0...9 {
            var c=UniChar(48+n),g=CGGlyph()
            guard CTFontGetGlyphsForCharacters(font,&c,&g,1),let path=CTFontCreatePathForGlyph(font,g,nil) else{continue}
            var bytes=[UInt8](repeating:0,count:64*64)
            bytes.withUnsafeMutableBytes{ p in
                let ctx=CGContext(data:p.baseAddress,width:64,height:64,bitsPerComponent:8,bytesPerRow:64,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0)!
                ctx.translateBy(x:4,y:8);ctx.setFillColor(gray:1,alpha:1);ctx.addPath(path);ctx.fillPath()
            }
            if let mask=shape((0..<64).map{ y in (0..<64).map{ bytes[y*64+$0]>120 } }){results.append((String(n),mask))}
        }
    }
    return results
}()
struct Card {
    let x:Int,y:Int,w:Int,source:RGB,target:RGB
}
struct MappingReader {
    let image:CGImage, width:Int,height:Int
    var pixels:[UInt8]
    init(_ url:URL)throws {
        guard let src=CGImageSourceCreateWithURL(url as CFURL,nil),let im=CGImageSourceCreateImageAtIndex(src,0,nil),
              im.width<=10000,im.height<=10000,im.width*im.height<=40_000_000 else{throw PreviewError("无法读取窗口截图。", "The window screenshot could not be read.")}
        image=im;width=im.width;height=im.height
        var bytes=[UInt8](repeating:0,count:width*height*4)
        let ok=bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let c=CGContext(data:raw.baseAddress,width:im.width,height:im.height,bitsPerComponent:8,bytesPerRow:im.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue) else{return false}
            c.draw(im,in:CGRect(x:0,y:0,width:im.width,height:im.height));return true
        }
        guard ok else{throw PreviewError("无法读取截图颜色。", "The screenshot colors could not be read.")};pixels=bytes
    }
    func pixel(_ x:Int,_ y:Int)->RGB{let i=4*(y*width+x);return RGB(Int(pixels[i]),Int(pixels[i+1]),Int(pixels[i+2]))}
    func median(_ x:Int,_ y:Int,_ r:Int)->RGB{
        var red=[Int](),green=[Int](),blue=[Int]()
        for j in (y-r)...(y+r){for i in (x-r)...(x+r){let c=pixel(i,j);red.append(c.r);green.append(c.g);blue.append(c.b)}}
        let m=red.count/2;return RGB(red.sorted()[m],green.sorted()[m],blue.sorted()[m])
    }
    func cards(_ originals:[RGB])->[Card]{
        var found=[Card]()
        func check(_ x:Int,_ y:Int,_ w:Int) {
            guard w>=65,w<=410 else{return}
            let scale=Double(w)/92
            func px(_ t:Double)->Int{x+Int((t*scale).rounded())}
            func py(_ t:Double)->Int{y+Int((t*scale).rounded())}
            guard px(90)<width,py(52)<height,py(-18)>0 else{return}
            let orig=median(px(78),py(-10),1)
            guard originals.contains(where:{$0.distance(orig)<15}),pixel(px(10),py(-10)).distance(orig)<14 else{return}
            // The wheel has a thin outline on each side of a solid spool swatch.
            let target=median(px(19),py(15),1)
            guard pixel(px(19),py(13)).distance(target)<13,pixel(px(19),py(17)).distance(target)<13 else{return}
            let row = py(15), base = pixel(px(3),row)
            var outlines=0
            for dx in 5...26 where pixel(px(Double(dx)),row).distance(base)>48 {outlines+=1}
            guard outlines>=2 else{return}
            // Distinguish the nozzle row, which has the dashed divider above it.
            var changes=0,old=false
            for i in px(8)...px(83){let value=pixel(i,py(30)).distance(base)>25;if old != value{changes+=1;old=value}}
            // A second independent anchor is the neutral bottom border at 84 DIP.
            var border=false
            for off in 60...67 where py(Double(off))<height{
                let c=pixel(px(70),py(Double(off)))
                if c.distance(RGB(172,172,172))<14 || c.distance(RGB(0,174,66))<40 {border=true}
            }
            guard border || changes>=5 else{return}
            if found.contains(where:{abs($0.x-x)<Int(5*scale)+2 && abs($0.y-y)<Int(4*scale)+1}){return}
            found.append(Card(x:x,y:y,w:w,source:orig,target:target))
        }
        for y in 2..<(height-2){
            var start = -1
            for x in 0..<width{
                let i=(y*width+x)*4
                let match=abs(Int(pixels[i])-172)<8 && abs(Int(pixels[i+1])-172)<8 && abs(Int(pixels[i+2])-172)<8
                if match && start<0 {start=x}
                if !match && start>=0 {if x-start>=65 {check(start,y,x-start)};start = -1}
            }
            if start>=0 && width-start>=65 {check(start,y,width-start)}
        }
        return found
    }
    func label(_ card:Card)->String?{
        let s=Double(card.w)/92
        let rect=CGRect(x:Double(card.x)+28*s,y:Double(card.y)+3*s,width:42*s,height:22*s).integral
        let bg=pixel(card.x+Int(69*s),card.y+Int(15*s))
        let x0=card.x+Int((29*s).rounded()),x1=card.x+Int((69*s).rounded())
        let y0=card.y+Int((5*s).rounded()),y1=card.y+Int((25*s).rounded())
        let mask=(y0..<y1).map{y in (x0..<x1).map{x in pixel(x,y).distance(bg)>86}}
        let columns=(0..<(x1-x0)).filter{x in mask.contains{$0[x]}}
        if let start=columns.first,let end=columns.last, end-start<15*Int(ceil(s)),columns.count==end-start+1,let sampled=shape(mask){
            let ranked=digits.map{ ref in (ref.0,zip(ref.1,sampled).filter{$0 != $1}.count)}.sorted{$0.1<$1.1}
            if let first=ranked.first,first.1<164,let second=ranked.first(where:{$0.0 != first.0}),second.1-first.1>18{return first.0}
            if ranked.first?.0=="6" || ranked.first?.0=="9" {return nil}
        }
        guard let cut=image.cropping(to:rect) else{return nil}
        let factor=4
        guard let ctx=CGContext(data:nil,width:cut.width*factor,height:cut.height*factor,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else{return nil}
        ctx.interpolationQuality = .high
        ctx.draw(cut,in:CGRect(x:0,y:0,width:cut.width*factor,height:cut.height*factor))
        guard let enlarged=ctx.makeImage() else{return nil}
        let req=VNRecognizeTextRequest();req.recognitionLevel = .accurate;req.usesLanguageCorrection=false;req.recognitionLanguages=["en-US"]
        try? VNImageRequestHandler(cgImage:enlarged,orientation:.up).perform([req])
        for ob in req.results ?? []{
            guard let candidate=ob.topCandidates(1).first else{continue}
            let v=candidate.string.trimmingCharacters(in:.whitespacesAndNewlines)
            if v.range(of:"^(?:[A-Z]{0,2}[- ]?[0-9]{1,2}|HT-[A-Z]|[0-9]-Ext)$",options:.regularExpression) != nil{return v}
        }
        return nil
    }
    func verifyWeight(_ grams:Double,_ first:Card)throws{
        let w=CGFloat(first.w),left=CGFloat(first.x),bottom=CGFloat(first.y)-w*0.45
        let box=CGRect(x:left+w*0.5,y:max(0,bottom-w*4.5),width:w*6.2,height:min(bottom,w*4.5)).intersection(CGRect(x:0,y:0,width:width,height:height))
        guard box.width>0,box.height>0,let crop=image.cropping(to:box) else{throw PreviewError("截图缺少任务预计克重，请导入完整发送窗口。", "The estimated filament weight is missing. Import a screenshot of the entire Send Print Job window.")}
        let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.recognitionLanguages=["en-US"];request.usesLanguageCorrection=false
        try VNImageRequestHandler(cgImage:crop,orientation:.up).perform([request])
        let pattern=try NSRegularExpression(pattern:#"(?i)([0-9]+(?:[.,][0-9]+)?)\s*g(?:\s|$)"#)
        for item in request.results ?? []{for t in item.topCandidates(2){
            let s=t.string as NSString
            for m in pattern.matches(in:t.string,range:NSRange(location:0,length:s.length)){
                if let n=Double(s.substring(with:m.range(at:1)).replacingOccurrences(of:",",with:".")),abs(n-grams)<=0.025+Double(24)*0.005{return}
            }
        }}
        throw PreviewError("窗口预计克重与所选切片未匹配（切片约 "+String(format:"%.2f g",grams)+"）。请选对工程或打印盘，并让截图包含预计耗材重量。", "The estimated weight does not match this slice (about "+String(format:"%.2f g",grams)+"). Check the project and plate and include the estimated weight in the screenshot.")
    }
    func read(colors:[String],slots:[Int],grams:Double?=nil)throws->[[String:Any]]{
        guard !slots.isEmpty,slots.allSatisfy({colors.indices.contains($0)}) else{throw PreviewError("切片没有可用于校验的耗材编号。", "The slice contains no filament IDs to verify.")}
        let expected=try slots.map{guard let c=RGB(colors[$0]) else{throw PreviewError("工程色无效。", "Invalid project filament color.")};return c}
        let candidates=cards(expected)
        // Align in screen reading order. A complete matching table is required,
        // including support-only tools and duplicate project colours.
        let sorted=candidates.sorted{$0.y==$1.y ? $0.x<$1.x : $0.y<$1.y}
        var rows=[[Card]]()
        for c in sorted {
            if let k=rows.indices.last,abs(rows[k][0].y-c.y)<max(3,c.w/15){rows[k].append(c)}else{rows.append([c])}
        }
        let ordered=rows.flatMap{$0.sorted{$0.x<$1.x}}
        var matches=[[Card]]()
        if ordered.count>=expected.count{
            for i in 0...(ordered.count-expected.count){
                let group=Array(ordered[i..<(i+expected.count)])
                if zip(group,expected).allSatisfy({$0.source.distance($1)<15}) && group.allSatisfy({abs($0.w-group[0].w)<max(9,group[0].w/13)}) {matches.append(group)}
            }
        }
        guard matches.count==1 else{throw PreviewError("未能唯一匹配全部 \(slots.count) 张耗材卡。请让发送窗口完整显示所有耗材卡，再读取或导入原尺寸截图。", "Could not match all \(slots.count) filament cards uniquely. Show every card and read again, or import a full-resolution screenshot.")}
        if let g=grams{try verifyWeight(g,matches[0][0])}
        var trayColors=[String:RGB]()
        return try zip(slots,matches[0]).map{slot,c in
            guard let label=label(c) else{throw PreviewError("耗材 \(slot+1) 的槽号未能确认。请使用清晰、完整的发送窗口截图。", "Could not confirm the AMS slot for filament \(slot+1). Import a clear screenshot of the entire Send Print Job window.")}
            if let other=trayColors[label],other.distance(c.target)>12{throw PreviewError("同一槽号出现两种颜色，无法确认本次映射。", "Two colors were detected for the same AMS slot. Check the mapping in Studio.")}
            trayColors[label]=c.target
            return ["slot":slot,"color":c.target.hex,"tray":label]
        }
    }
}
