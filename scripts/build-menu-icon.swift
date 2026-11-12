import Foundation
import CoreGraphics
import ImageIO

// Preserve the PNG alpha channel. Converting through JPEG makes macOS's
// template rendering tint the entire icon rectangle instead of its silhouette.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("resources/LingoSphereMenu.png")
let output = root.appendingPathComponent("resources/LingoSphereMenu.pdf")
guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
  fatalError("Cannot read menu icon PNG")
}
var bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
guard let consumer = CGDataConsumer(url: output as CFURL),
      let pdf = CGContext(consumer: consumer, mediaBox: &bounds, nil) else {
  fatalError("Cannot create menu icon PDF")
}
pdf.beginPDFPage(nil)
pdf.draw(image, in: bounds)
pdf.endPDFPage()
pdf.closePDF()

// Test the PDF that will actually ship, including the alpha mask used by TIS.
guard let document = CGPDFDocument(output as CFURL), let page = document.page(at: 1),
      page.getBoxRect(.mediaBox) == bounds,
      let bitmap = CGContext(data: nil, width: 64, height: 64,
        bitsPerComponent: 8, bytesPerRow: 256,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let pixels = bitmap.data?.assumingMemoryBound(to: UInt8.self) else {
  fatalError("Cannot validate menu icon PDF")
}
bitmap.scaleBy(x: 4, y: 4)
bitmap.drawPDFPage(page)
let opaque = (0..<4096).filter { pixels[$0 * 4 + 3] > 240 }.count
let transparent = (0..<4096).filter { pixels[$0 * 4 + 3] == 0 }.count
precondition(pixels[3] == 0 && pixels[63 * 4 + 3] == 0,
             "Menu icon corners must be transparent")
precondition(opaque > 500 && transparent > 500,
             "Menu icon must contain both visible artwork and transparent background")
print("Menu icon validated: 16×16 pt; \(opaque) opaque and \(transparent) transparent pixels")
