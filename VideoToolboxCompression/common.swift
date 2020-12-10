//
//  common.swift
//  heic_demo
//
//  Created by Jerry Tian on 2020/11/25.
//

import UIKit
import AVFoundation
import VideoToolbox

let cvPxFormat = kCVPixelFormatType_420YpCbCr10BiPlanarFullRange

// Good ones
// 
// kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
// kCVPixelFormatType_64RGBALE
// kCVPixelFormatType_32ARGB

// Bad ones
//
// kCVPixelFormatType_64ARGB: no buffer got
// kCVPixelFormatType_48RGB: no buffer got
// kCVPixelFormatType_32RGBA: wrong buffer, always green.
//

enum ImageCompressionError: Error {
  case NotSupported
  case ImageMissing
  case CanNotFinalize
}

enum VideoCompressionError: Error {
  case NotSupported
  case ImageMissing
  case CanNotFinalize
}

enum FrameCaptureStrategy {
    case FromAVAssetImageGenerator
    case FromDisplayLinkCVBuffer
}

enum SessionSetupResult {
    case success
    case notAuthorized
    case configurationFailed
}


extension FourCharCode {
    private static let bytesSize = MemoryLayout<Self>.size
    var codeString: String {
        get {
            withUnsafePointer(to: bigEndian) { pointer in
                pointer.withMemoryRebound(to: UInt8.self, capacity: Self.bytesSize) { bytes in
                    String(bytes: UnsafeBufferPointer(start: bytes,
                                                      count: Self.bytesSize),
                           encoding: .macOSRoman)!
                }
            }
        }
    }
}

extension OSStatus {
    var codeString: String {
        FourCharCode(bitPattern: self).codeString
    }
}

private func fourChars(_ string: String) -> String? {
    string.count == MemoryLayout<FourCharCode>.size ? string : nil
}
private func fourBytes(_ string: String) -> Data? {
    fourChars(string)?.data(using: .macOSRoman, allowLossyConversion: false)
}
func stringCode(_ string: String) -> FourCharCode {
    fourBytes(string)?.withUnsafeBytes { $0.load(as: FourCharCode.self).byteSwapped } ?? 0
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
    
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {
        
        var uniqueDevicePositions = [AVCaptureDevice.Position]()
        
        for device in devices where !uniqueDevicePositions.contains(device.position) {
            uniqueDevicePositions.append(device.position)
        }
        
        return uniqueDevicePositions.count
    }
}

extension URL {
    func fileSize() -> Double {
        var fileSize: Double = 0.0
        var fileSizeValue = 0.0
        try? fileSizeValue = (self.resourceValues(forKeys: [URLResourceKey.fileSizeKey]).allValues.first?.value as! Double?)!
        if fileSizeValue > 0.0 {
            fileSize = (Double(fileSizeValue) / (1024 * 1024))
        }
        return fileSize
    }
}

extension URL {
    public func bytesSizeIfAvailable() -> Int {
        do {
            let resources = try self.resourceValues(forKeys:[.fileSizeKey])
            let fileSize = resources.fileSize!
            return fileSize
        } catch {
            return -1
        }
    }
    
    var typeIdentifier: String? {
        return (try? resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier
    }
    
    var localizedName: String? {
        return (try? resourceValues(forKeys: [.localizedNameKey]))?.localizedName
    }
}
