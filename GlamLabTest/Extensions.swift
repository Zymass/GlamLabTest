//
//  Extensions.swift
//  GlamLabTest
//
//  Created by Илья Филяев on 05.02.2023.
//

import UIKit
import CoreGraphics
import Accelerate
import CoreML


extension CGImage {
    
    /**
     Creates a new CGImage from an array of RGBA bytes.
     */
    public class func fromByteArrayRGBA(_ bytes: [UInt8],
                                        width: Int,
                                        height: Int) -> CGImage? {
        return fromByteArray(bytes, width: width, height: height,
                             bytesPerRow: width * 4,
                             colorSpace: CGColorSpaceCreateDeviceRGB(),
                             alphaInfo: .premultipliedLast)
    }
    
    /**
     Creates a new CGImage from an array of grayscale bytes.
     */
    public class func fromByteArrayGray(_ bytes: [UInt8],
                                        width: Int,
                                        height: Int) -> CGImage? {
        return fromByteArray(bytes, width: width, height: height,
                             bytesPerRow: width,
                             colorSpace: CGColorSpaceCreateDeviceGray(),
                             alphaInfo: .none)
    }
    
    class func fromByteArray(_ bytes: [UInt8],
                             width: Int,
                             height: Int,
                             bytesPerRow: Int,
                             colorSpace: CGColorSpace,
                             alphaInfo: CGImageAlphaInfo) -> CGImage? {
        return bytes.withUnsafeBytes { ptr in
            let context = CGContext(data: UnsafeMutableRawPointer(mutating: ptr.baseAddress!),
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: alphaInfo.rawValue)
            return context?.makeImage()
        }
    }
}

public protocol MultiArrayType: Comparable {
    static var multiArrayDataType: MLMultiArrayDataType { get }
    static func +(lhs: Self, rhs: Self) -> Self
    static func -(lhs: Self, rhs: Self) -> Self
    static func *(lhs: Self, rhs: Self) -> Self
    static func /(lhs: Self, rhs: Self) -> Self
    init(_: Int)
    var toUInt8: UInt8 { get }
}

extension Double: MultiArrayType {
    public static var multiArrayDataType: MLMultiArrayDataType { return .double }
    public var toUInt8: UInt8 { return UInt8(self) }
}

extension Float: MultiArrayType {
    public static var multiArrayDataType: MLMultiArrayDataType { return .float32 }
    public var toUInt8: UInt8 { return UInt8(self) }
}

extension Int32: MultiArrayType {
    public static var multiArrayDataType: MLMultiArrayDataType { return .int32 }
    public var toUInt8: UInt8 { return UInt8(self) }
}

extension MLMultiArray {
    /**
     Converts the multi-array to a CGImage.
     
     The multi-array must have at least 2 dimensions for a grayscale image, or
     at least 3 dimensions for a color image.
     
     The default expected shape is (height, width) or (channels, height, width).
     However, you can change this using the `axes` parameter. For example, if
     the array shape is (1, height, width, channels), use `axes: (3, 1, 2)`.
     
     If `channel` is not nil, only converts that channel to a grayscale image.
     This lets you visualize individual channels from a multi-array with more
     than 4 channels.
     
     Otherwise, converts all channels. In this case, the number of channels in
     the multi-array must be 1 for grayscale, 3 for RGB, or 4 for RGBA.
     
     Use the `min` and `max` parameters to put the values from the array into
     the range [0, 255], if not already:
     
     - `min`: should be the smallest value in the data; this will be mapped to 0.
     - `max`: should be the largest value in the data; will be mapped to 255.
     
     For example, if the range of the data in the multi-array is [-1, 1], use
     `min: -1, max: 1`. If the range is already [0, 255], then use the defaults.
     */
    public func cgImage(min: Double = 0,
                        max: Double = 255,
                        channel: Int? = nil,
                        axes: (Int, Int, Int)? = nil) -> CGImage? {
        switch self.dataType {
        case .double:
            return _image(min: min, max: max, channel: channel, axes: axes)
        case .float32:
            return _image(min: Float(min), max: Float(max), channel: channel, axes: axes)
        case .int32:
            return _image(min: Int32(min), max: Int32(max), channel: channel, axes: axes)
        default:
            fatalError("Unsupported data type \(dataType.rawValue)")
        }
    }
    
    /**
     Helper function that allows us to use generics. The type of `min` and `max`
     is also the dataType of the MLMultiArray.
     */
    private func _image<T: MultiArrayType>(min: T,
                                           max: T,
                                           channel: Int?,
                                           axes: (Int, Int, Int)?) -> CGImage? {
        if let (b, w, h, c) = toRawBytes(min: min, max: max, channel: channel, axes: axes) {
            if c == 1 {
                return CGImage.fromByteArrayGray(b, width: w, height: h)
            } else {
                return CGImage.fromByteArrayRGBA(b, width: w, height: h)
            }
        }
        return nil
    }
    
    /**
     Converts the multi-array into an array of RGBA or grayscale pixels.
     
     - Note: This is not particularly fast, but it is flexible. You can change
     the loops to convert the multi-array whichever way you please.
     
     - Note: The type of `min` and `max` must match the dataType of the
     MLMultiArray object.
     
     - Returns: tuple containing the RGBA bytes, the dimensions of the image,
     and the number of channels in the image (1, 3, or 4).
     */
    public func toRawBytes<T: MultiArrayType>(min: T,
                                              max: T,
                                              channel: Int? = nil,
                                              axes: (Int, Int, Int)? = nil)
    -> (bytes: [UInt8], width: Int, height: Int, channels: Int)? {
        // MLMultiArray with unsupported shape?
        if shape.count < 2 {
            print("Cannot convert MLMultiArray of shape \(shape) to image")
            return nil
        }
        
        // Figure out which dimensions to use for the channels, height, and width.
        let channelAxis: Int
        let heightAxis: Int
        let widthAxis: Int
        if let axes = axes {
            channelAxis = axes.0
            heightAxis = axes.1
            widthAxis = axes.2
            guard channelAxis >= 0 && channelAxis < shape.count &&
                    heightAxis >= 0 && heightAxis < shape.count &&
                    widthAxis >= 0 && widthAxis < shape.count else {
                print("Invalid axes \(axes) for shape \(shape)")
                return nil
            }
        } else if shape.count == 2 {
            // Expected shape for grayscale is (height, width)
            heightAxis = 0
            widthAxis = 1
            channelAxis = -1 // Never be used
        } else {
            // Expected shape for color is (channels, height, width)
            channelAxis = 0
            heightAxis = 1
            widthAxis = 2
        }
        
        let height = self.shape[heightAxis].intValue
        let width = self.shape[widthAxis].intValue
        let yStride = self.strides[heightAxis].intValue
        let xStride = self.strides[widthAxis].intValue
        
        let channels: Int
        let cStride: Int
        let bytesPerPixel: Int
        let channelOffset: Int
        
        // MLMultiArray with just two dimensions is always grayscale. (We ignore
        // the value of channelAxis here.)
        if shape.count == 2 {
            channels = 1
            cStride = 0
            bytesPerPixel = 1
            channelOffset = 0
            
            // MLMultiArray with more than two dimensions can be color or grayscale.
        } else {
            let channelDim = self.shape[channelAxis].intValue
            if let channel = channel {
                if channel < 0 || channel >= channelDim {
                    print("Channel must be -1, or between 0 and \(channelDim - 1)")
                    return nil
                }
                channels = 1
                bytesPerPixel = 1
                channelOffset = channel
            } else if channelDim == 1 {
                channels = 1
                bytesPerPixel = 1
                channelOffset = 0
            } else {
                if channelDim != 3 && channelDim != 4 {
                    print("Expected channel dimension to have 1, 3, or 4 channels, got \(channelDim)")
                    return nil
                }
                channels = channelDim
                bytesPerPixel = 4
                channelOffset = 0
            }
            cStride = self.strides[channelAxis].intValue
        }
        
        // Allocate storage for the RGBA or grayscale pixels. Set everything to
        // 255 so that alpha channel is filled in if only 3 channels.
        let count = height * width * bytesPerPixel
        var pixels = [UInt8](repeating: 255, count: count)
        
        // Grab the pointer to MLMultiArray's memory.
        var ptr = UnsafeMutablePointer<T>(OpaquePointer(self.dataPointer))
        ptr = ptr.advanced(by: channelOffset * cStride)
        
        // Loop through all the pixels and all the channels and copy them over.
        for c in 0..<channels {
            for y in 0..<height {
                for x in 0..<width {
                    let value = ptr[c*cStride + y*yStride + x*xStride]
                    let scaled = (value - min) * T(255) / (max - min)
                    let pixel = clamp(scaled, min: T(0), max: T(255)).toUInt8
                    pixels[(y*width + x)*bytesPerPixel + c] = pixel
                }
            }
        }
        return (pixels, width, height, channels)
    }
    
    /** Ensures that `x` is in the range `[min, max]`. */
    public func clamp<T: Comparable>(_ x: T, min: T, max: T) -> T {
        if x < min { return min }
        if x > max { return max }
        return x
    }
    
    
    public func image(min: Double = 0,
                      max: Double = 255,
                      channel: Int? = nil,
                      axes: (Int, Int, Int)? = nil) -> UIImage? {
        let cgImg = cgImage(min: min, max: max, channel: channel, axes: axes)
        return cgImg.map { UIImage(cgImage: $0) }
    }
}

extension UIImage {
    
    func removeBackground() -> UIImage? {
        guard let model = getDeepLabV3Model() else { return nil }
        
        // standart size
        let width: CGFloat = 513
        let height: CGFloat = 513
        let resizedImage = resized(to: CGSize(width: height, height: height), scale: 1)
        
        guard let pixelBuffer = resizedImage.pixelBuffer(width: Int(width), height: Int(height)),
              let outputPredictionImage = try? model.prediction(image: pixelBuffer),
              let outputImage = outputPredictionImage.semanticPredictions.image(min: 0, max: 1, axes: (0, 0, 1)),
              let outputCIImage = CIImage(image: outputImage),
              let maskImage = outputCIImage.removeWhitePixels() else { return nil }
        
        guard let resizedCIImage = CIImage(image: resizedImage),
              let compositedImage = resizedCIImage.composite(with: maskImage) else { return nil }
        let finalImage = UIImage(ciImage: compositedImage)
            .resized(to: CGSize(width: size.width, height: size.height))
        return finalImage
    }
    
    private func getDeepLabV3Model() -> DeepLabV3? {
        do {
            let config = MLModelConfiguration()
            return try DeepLabV3(configuration: config)
        } catch {
            print("error configure DeepLabV3")
            return nil
        }
    }
    
    func resized(to newSize: CGSize, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let image = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        return image
    }
    
    func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        return pixelBuffer(width: width, height: height,
                           pixelFormatType: kCVPixelFormatType_32ARGB,
                           colorSpace: CGColorSpaceCreateDeviceRGB(),
                           alphaInfo: .noneSkipFirst)
    }
    
    func pixelBufferGray(width: Int, height: Int) -> CVPixelBuffer? {
        return pixelBuffer(width: width, height: height,
                           pixelFormatType: kCVPixelFormatType_OneComponent8,
                           colorSpace: CGColorSpaceCreateDeviceGray(),
                           alphaInfo: .none)
    }
    
    /**
     Resizes the image to `width` x `height` and converts it to a `CVPixelBuffer`
     with the specified pixel format, color space, and alpha channel.
     */
    public func pixelBuffer(width: Int, height: Int,
                            pixelFormatType: OSType,
                            colorSpace: CGColorSpace,
                            alphaInfo: CGImageAlphaInfo) -> CVPixelBuffer? {
        var maybePixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
             kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue]
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         width,
                                         height,
                                         pixelFormatType,
                                         attrs as CFDictionary,
                                         &maybePixelBuffer)
        
        guard status == kCVReturnSuccess, let pixelBuffer = maybePixelBuffer else {
            return nil
        }
        
        let flags = CVPixelBufferLockFlags(rawValue: 0)
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(pixelBuffer, flags) else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, flags) }
        
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                      space: colorSpace,
                                      bitmapInfo: alphaInfo.rawValue)
        else {
            return nil
        }
        
        UIGraphicsPushContext(context)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        self.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        
        return pixelBuffer
    }
    
    
}

extension CIImage {
    
    func removeWhitePixels() -> CIImage? {
        let chromaCIFilter = chromaKeyFilter()
        chromaCIFilter?.setValue(self, forKey: kCIInputImageKey)
        return chromaCIFilter?.outputImage
    }
    
    func composite(with mask: CIImage) -> CIImage? {
        return CIFilter(
            name: "CISourceOutCompositing",
            parameters: [
                kCIInputImageKey: self,
                kCIInputBackgroundImageKey: mask
            ]
        )?.outputImage
    }
    
    private func chromaKeyFilter() -> CIFilter? {
        let size = 64
        var cubeRGB = [Float]()
        
        for z in 0 ..< size {
            let blue = CGFloat(z) / CGFloat(size - 1)
            for y in 0 ..< size {
                let green = CGFloat(y) / CGFloat(size - 1)
                for x in 0 ..< size {
                    let red = CGFloat(x) / CGFloat(size - 1)
                    let brightness = getBrightness(red: red, green: green, blue: blue)
                    let alpha: CGFloat = brightness == 1 ? 0 : 1
                    cubeRGB.append(Float(red * alpha))
                    cubeRGB.append(Float(green * alpha))
                    cubeRGB.append(Float(blue * alpha))
                    cubeRGB.append(Float(alpha))
                }
            }
        }
        
        let data = Data(buffer: UnsafeBufferPointer(start: &cubeRGB, count: cubeRGB.count))
        
        let colorCubeFilter = CIFilter(
            name: "CIColorCube",
            parameters: [
                "inputCubeDimension": size,
                "inputCubeData": data
            ]
        )
        return colorCubeFilter
    }
    
    private func getBrightness(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        let color = UIColor(red: red, green: green, blue: blue, alpha: 1)
        var brightness: CGFloat = 0
        color.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil)
        return brightness
    }
}
