import AppKit

let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(red: 0.13, green: 0.24, blue: 0.22, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
NSColor(red: 0.87, green: 0.91, blue: 0.75, alpha: 1).setStroke()
let plan = NSBezierPath()
plan.move(to: NSPoint(x: 250, y: 250)); plan.line(to: NSPoint(x: 250, y: 774))
plan.line(to: NSPoint(x: 774, y: 774)); plan.line(to: NSPoint(x: 774, y: 430))
plan.line(to: NSPoint(x: 580, y: 430)); plan.line(to: NSPoint(x: 580, y: 250)); plan.close()
plan.lineWidth = 34; plan.lineJoinStyle = .miter; plan.stroke()
let ruler = NSBezierPath()
ruler.move(to: NSPoint(x: 200, y: 150)); ruler.line(to: NSPoint(x: 824, y: 150))
for x in [200, 824] { ruler.move(to: NSPoint(x: x, y: 115)); ruler.line(to: NSPoint(x: x, y: 185)) }
ruler.lineWidth = 10; ruler.stroke()
NSColor(red: 0.90, green: 0.49, blue: 0.29, alpha: 1).setStroke()
let window = NSBezierPath()
window.move(to: NSPoint(x: 410, y: 760)); window.line(to: NSPoint(x: 630, y: 760))
window.move(to: NSPoint(x: 410, y: 790)); window.line(to: NSPoint(x: 630, y: 790))
window.lineWidth = 11; window.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let output = CommandLine.arguments[1]
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
