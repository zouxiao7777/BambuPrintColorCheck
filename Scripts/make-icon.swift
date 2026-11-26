import AppKit

// Place the generated artwork on the same transparent canvas at every Dock size.
let arguments = CommandLine.arguments
let source = URL(fileURLWithPath: arguments[1])
let destination = URL(fileURLWithPath: arguments[2])
guard let image = NSImage(contentsOf: source) else { exit(1) }
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let masterSize = 1024
let master = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:masterSize, pixelsHigh:masterSize,
                              bitsPerSample:8, samplesPerPixel:4, hasAlpha:true, isPlanar:false,
                              colorSpaceName:.deviceRGB, bytesPerRow:0, bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: master)
NSGraphicsContext.current?.imageInterpolation = .high
let tile = NSRect(x: 92, y: 92, width: 840, height: 840)
NSBezierPath(roundedRect: tile, xRadius: 184, yRadius: 184).addClip()
let sourceRect = NSRect(origin:.zero, size:image.size).insetBy(dx:image.size.width*0.040, dy:image.size.height*0.040)
image.draw(in:tile, from:sourceRect, operation:.sourceOver, fraction:1)
NSGraphicsContext.restoreGraphicsState()
let artwork = NSImage(size:NSSize(width:masterSize,height:masterSize))
artwork.addRepresentation(master)
for base in [16,32,128,256,512] {
    for scale in [1,2] {
        let size = base * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:size, pixelsHigh:size,
                                      bitsPerSample:8, samplesPerPixel:4, hasAlpha:true, isPlanar:false,
                                      colorSpaceName:.deviceRGB, bytesPerRow:0, bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        artwork.draw(in:NSRect(x:0,y:0,width:size,height:size))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let name = "icon_\(base)x\(base)\(suffix).png"
        try bitmap.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent(name))
    }
}
