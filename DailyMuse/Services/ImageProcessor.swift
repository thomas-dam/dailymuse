import AppKit
import CoreImage

/// Post-processes generated images for e-ink or other display targets.
enum ImageProcessor {

    /// Convert to 1-bit dithered grayscale suitable for e-ink displays.
    /// Uses Core Image + Core Graphics to avoid the ImageMagick dependency.
    static func processForEink(_ imageData: Data, width: Int = 800, height: Int = 480) throws -> Data {
        guard let ciImage = CIImage(data: imageData) else {
            throw DailyMuseError.imageError("Could not load image for processing")
        }

        let context = CIContext()

        // 1. Convert to grayscale
        let grayscaleFilter = CIFilter(name: "CIColorMonochrome")!
        grayscaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
        grayscaleFilter.setValue(CIColor(red: 0.7, green: 0.7, blue: 0.7), forKey: "inputColor")
        grayscaleFilter.setValue(1.0, forKey: "inputIntensity")

        guard let grayImage = grayscaleFilter.outputImage else {
            throw DailyMuseError.imageError("Grayscale conversion failed")
        }

        // 2. Boost contrast for better dithering
        let contrastFilter = CIFilter(name: "CIColorControls")!
        contrastFilter.setValue(grayImage, forKey: kCIInputImageKey)
        contrastFilter.setValue(0.5, forKey: "inputContrast")      // boost
        contrastFilter.setValue(0.05, forKey: "inputBrightness")   // slight lift for white-dominant

        guard let contrastImage = contrastFilter.outputImage else {
            throw DailyMuseError.imageError("Contrast adjustment failed")
        }

        // 3. Scale to target resolution
        let scaleX = CGFloat(width) / contrastImage.extent.width
        let scaleY = CGFloat(height) / contrastImage.extent.height
        let scale = min(scaleX, scaleY)

        let scaleFilter = CIFilter(name: "CILanczosScaleTransform")!
        scaleFilter.setValue(contrastImage, forKey: kCIInputImageKey)
        scaleFilter.setValue(scale, forKey: kCIInputScaleKey)
        scaleFilter.setValue(1.0, forKey: "inputAspectRatio")

        guard let scaledImage = scaleFilter.outputImage else {
            throw DailyMuseError.imageError("Scaling failed")
        }

        // 4. Render to CGImage
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            throw DailyMuseError.imageError("CGImage rendering failed")
        }

        // 5. Apply Floyd-Steinberg dithering to 1-bit
        let dithered = try floydSteinbergDither(cgImage)

        // 6. Export as PNG
        let rep = NSBitmapImageRep(cgImage: dithered)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw DailyMuseError.imageError("PNG encoding failed")
        }

        return pngData
    }

    /// Floyd-Steinberg dithering to 1-bit black and white.
    private static func floydSteinbergDither(_ source: CGImage) throws -> CGImage {
        let w = source.width
        let h = source.height

        // Get grayscale pixel data
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let ctx = CGContext(
                data: nil, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            throw DailyMuseError.imageError("Could not create grayscale context")
        }

        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let pixelData = ctx.data else {
            throw DailyMuseError.imageError("No pixel data")
        }

        let pixels = pixelData.bindMemory(to: UInt8.self, capacity: w * h)

        // Use Float buffer for error diffusion
        var buffer = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            buffer[i] = Float(pixels[i])
        }

        // Floyd-Steinberg error diffusion
        for y in 0..<h {
            for x in 0..<w {
                let idx = y * w + x
                let oldPixel = buffer[idx]
                let newPixel: Float = oldPixel > 128 ? 255 : 0
                let error = oldPixel - newPixel
                buffer[idx] = newPixel

                if x + 1 < w       { buffer[idx + 1]     += error * 7.0 / 16.0 }
                if y + 1 < h {
                    if x > 0       { buffer[(y+1)*w + x-1] += error * 3.0 / 16.0 }
                                     buffer[(y+1)*w + x]   += error * 5.0 / 16.0
                    if x + 1 < w   { buffer[(y+1)*w + x+1] += error * 1.0 / 16.0 }
                }
            }
        }

        // Write back
        for i in 0..<(w * h) {
            pixels[i] = UInt8(max(0, min(255, buffer[i])))
        }

        guard let result = ctx.makeImage() else {
            throw DailyMuseError.imageError("Failed to create dithered image")
        }

        return result
    }
}
