//
//  ViewController.swift
//  VideoToolboxCompression
//
//  Created by tomisacat on 12/08/2017.
//  Copyright © 2017 tomisacat. All rights reserved.
//
//  greenpig 2017.12：增加HEVC的支持，使用方法如下:
//  1. 确认下面的H265变量是true
//  2. 翻译App在iPhone 7以上设备执行，点击Click Me开始录像，再次点击结束
//  3. 在XCode中Window->Devices and Simualtors->选择App点下面齿轮->Download Container
//  4. Container中有tmp/temp.h265文件就是 raw h265 data
//  5. mp4box -add temp.h265 temp.h265.mp4就得到可以用QuickTime播放的HEVC文件了
//

import UIKit
import AVFoundation
import VideoToolbox

fileprivate var NALUHeader: [UInt8] = [0, 0, 0, 1]

let H265 = false
var frameCount = 0

// 事实上，使用 VideoToolbox 硬编码的用途大多是推流编码后的 NAL Unit 而不是写入到本地一个 H.264 文件
// 如果你想保存到本地，使用 AVAssetWriter 是一个更好的选择，它内部也是会硬编码的
func compressionOutputCallback(outputCallbackRefCon: UnsafeMutableRawPointer?,
                               sourceFrameRefCon: UnsafeMutableRawPointer?,
                               status: OSStatus,
                               infoFlags: VTEncodeInfoFlags,
                               sampleBuffer: CMSampleBuffer?) -> Swift.Void {
    guard status == noErr else {
        print("error: \(status)")
        return
    }
    
    if infoFlags == .frameDropped {
        print("frame dropped")
        return
    }
    
    guard let sampleBuffer = sampleBuffer else {
        print("sampleBuffer is nil")
        return
    }
    
    if CMSampleBufferDataIsReady(sampleBuffer) != true {
        print("sampleBuffer data is not ready")
        return
    }

    // 调试信息
//    let desc = CMSampleBufferGetFormatDescription(sampleBuffer)
//    let extensions = CMFormatDescriptionGetExtensions(desc!)
//    print("extensions: \(extensions!)")
//
//    let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
//    print("sample count: \(sampleCount)")
//
//    let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer)!
//    var length: Int = 0
//    var dataPointer: UnsafeMutablePointer<Int8>?
//    CMBlockBufferGetDataPointer(dataBuffer, 0, nil, &length, &dataPointer)
//    print("length: \(length), dataPointer: \(dataPointer!)")
    // 调试信息结束
    
    let vc: ViewController = Unmanaged.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
    
    print("encoded frame: \(frameCount)")
    vc.writeCompressedFrame(frame: sampleBuffer)
}

func generateTmpMovFileURL() -> URL {
    let outputFileName = ProcessInfo().globallyUniqueString
    let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
    return URL(fileURLWithPath: outputFilePath)
}

class ViewController: UIViewController {
    
    
    let captureSession = AVCaptureSession()
    var captureDevice: AVCaptureDevice? = nil
    let captureQueue = DispatchQueue(label: "videotoolbox.compression.capture")
    let compressionQueue = DispatchQueue(label: "videotoolbox.compression.compression")
    let writingQueue = DispatchQueue(label: "videotoolbox.compression.writing")
    
    var lastFrameTime = CMTimeMake(0, 600)
    lazy var preview: AVCaptureVideoPreviewLayer = {
        let preview = AVCaptureVideoPreviewLayer(session: self.captureSession)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        
        return preview
    }()
    
    var compressionSession: VTCompressionSession?
    
    var outputAssetURL:URL?
    var assetWriter:AVAssetWriter?
    var assetWriterInput:AVAssetWriterInput?
    var isCapturing: Bool = false
    
    var windowOrientation: UIInterfaceOrientation {
        return view.window?.windowScene?.interfaceOrientation ?? .unknown
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.captureQueue.async {
            self.captureSession.beginConfiguration()
            
            defer {
                self.captureSession.commitConfiguration()
            }
            
            
            self.captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)!
            
            CameraUtil.dumpAllFormats(with: self.captureDevice!.formats)
            
            let input = try! AVCaptureDeviceInput(device: self.captureDevice!)
            if self.captureSession.canAddInput(input) {
                self.captureSession.addInput(input)
            }
            
            // AVCaptureDevice.activeFormat will give enough hint for output(pixel format, etc),
            // no explicit setting here.
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: self.captureQueue)
            if self.captureSession.canAddOutput(output) {
                self.captureSession.addOutput(output)
            }
            
            if let connection = output.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    DispatchQueue.main.async {
                        var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                        if self.windowOrientation != .unknown {
                            if let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: self.windowOrientation) {
                                initialVideoOrientation = videoOrientation
                            }
                        }
                        
                        connection.videoOrientation = AVCaptureVideoOrientation(rawValue: initialVideoOrientation.rawValue)!
                        
                    }
                }
            }
            
        }
        
        self.captureQueue.asyncAfter(deadline: .now() + 0.3) {
            
            
            self.captureSession.beginConfiguration()
            
//            CameraUtil.setHighestVideoCaptureMode(with: self.captureDevice!)
            
            do {
                try self.captureDevice!.lockForConfiguration()
                defer {
                    self.captureDevice!.unlockForConfiguration()
                }
                
                if let f_4k_hlg = CameraUtil.find4kHDR_HLG_BT2020_Format(with: self.captureDevice!.formats) {
                    self.captureDevice!.activeFormat = f_4k_hlg
                } else {
                    throw VideoCompressionError.NotSupported
                }
                print("camera format set to: \(self.captureDevice!.activeFormat)")
            } catch {
                print("configure camera failed: \(error)")
            }
            
            self.captureSession.commitConfiguration()
            
            self.captureSession.startRunning()
        }
    }
    
    override func viewDidLayoutSubviews() {
        preview.frame = view.bounds
        
        let button = UIButton(type: .roundedRect)
        button.setTitle("Click Me", for: .normal)
        button.backgroundColor = .red
        button.addTarget(self, action: #selector(startOrNot), for: .touchUpInside)
        button.frame = CGRect(x: 100, y: 200, width: 100, height: 40)

        view.addSubview(button)
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        let pv = self.preview
        
        if let videoPreviewLayerConnection = pv.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation),
                deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                    return
            }
            
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }
    }
}

extension ViewController {
    @objc func startOrNot() {
        if isCapturing {
            stopCapture()
        } else {
            startCapture()
        }
    }
    
    func startCapture() {
        isCapturing = true
        
        self.writingQueue.async {
            do {
                self.outputAssetURL = generateTmpMovFileURL()
                self.assetWriter = try AVAssetWriter(outputURL: self.outputAssetURL!, fileType: .mov)
                //outputSettings = nil => no compression, buffer is in compressed state already.
                
//                var settings:[String : Any] = [:]
//                var colorProps:[String: Any] = [:]
//
//                colorProps[AVVideoColorPrimariesKey] = AVVideoColorPrimaries_ITU_R_2020
//                colorProps[AVVideoTransferFunctionKey] = AVVideoTransferFunction_ITU_R_2100_HLG
//                colorProps[AVVideoYCbCrMatrixKey] = AVVideoYCbCrMatrix_ITU_R_2020
//
//                settings[AVVideoColorPropertiesKey] = colorProps
                
                self.assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
                
                if (self.assetWriter!.canAdd(self.assetWriterInput!)) {
                    self.assetWriter?.add(self.assetWriterInput!)
                } else {
                    throw VideoCompressionError.NotSupported
                }
                
                self.assetWriter?.startWriting()
                self.assetWriter?.startSession(atSourceTime: self.lastFrameTime)
            } catch {
                print("can not init MOV writer. \(error)")
            }
        }
    }
    
    func stopCapture() {
        isCapturing = false
        
        guard let compressionSession = compressionSession else {
            return
        }
        
        self.captureQueue.async {
            VTCompressionSessionCompleteFrames(compressionSession, kCMTimeInvalid)
            VTCompressionSessionInvalidate(compressionSession)
            self.compressionSession = nil
        }
        
        self.writingQueue.async {
            self.assetWriterInput?.markAsFinished()
            self.assetWriter?.endSession(atSourceTime: self.lastFrameTime)
            self.assetWriter?.finishWriting {
                if (self.assetWriter?.status == .completed) {
                    print("MOV file written ok. \(self.outputAssetURL!.fileSize()))MB")
                } else {
                    print("MOV file written with error: \(String(describing: self.assetWriter!.error))")
                }
                self.assetWriterInput = nil
                self.assetWriter = nil
                
                
                DispatchQueue.main.async {
                    MediaUtil.systemShareAction(url: self.outputAssetURL!, from: self.view)
                }
            }
        }
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func dumpCMBufferInfo(_ sampleBuffer: CMSampleBuffer) {
//
//        if (frameCount % 120 != 1) {
//            return
//        }
        
        guard let pixelbuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
//
//        if CVPixelBufferIsPlanar(pixelbuffer) {
//            print("planar format type: \(CVPixelBufferGetPixelFormatType(pixelbuffer).codeString)")
//        }
//
//         var desc: CMFormatDescription?
//         CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelbuffer, &desc)
//         let extensions = CMFormatDescriptionGetExtensions(desc!)
//         print("format extensions: \(extensions!)")
        
        print("dump buffer info: \(pixelbuffer)")
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelbuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        frameCount += 1
        self.lastFrameTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
        
        if compressionSession == nil {
            let width = CVPixelBufferGetWidth(pixelbuffer)
            let height = CVPixelBufferGetHeight(pixelbuffer)
            
            print("width: \(width), height: \(height)")

            let status = VTCompressionSessionCreate(kCFAllocatorDefault,
                                       Int32(width),
                                       Int32(height),
                                       H265 ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264,
                                       nil, nil, nil,
                                       compressionOutputCallback,
                                       UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                                       &compressionSession)
            
            guard let c = compressionSession else {
                print("Error creating compression session: \(status)")
                return
            }
            
            // set profile to Main
            if H265 {
                VTSessionSetProperty(c, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main10_AutoLevel)
            } else {
                VTSessionSetProperty(c, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel)
            }
            // capture from camera, so it's real time
            VTSessionSetProperty(c, kVTCompressionPropertyKey_RealTime, true as CFTypeRef)
            // 关键帧间隔
            VTSessionSetProperty(c, kVTCompressionPropertyKey_MaxKeyFrameInterval, 1 as CFTypeRef)
            // 比特率和速率
//            let bitRate =  width * height * 4 * 32
//            print("target bit rate: \(bitRate/1000/1000)Mbps")
//            VTSessionSetProperty(c, kVTCompressionPropertyKey_AverageBitRate, bitRate as CFTypeRef)
//            VTSessionSetProperty(c, kVTCompressionPropertyKey_Quality, 1.0 as CFTypeRef)
            VTSessionSetProperty(c, kVTCompressionPropertyKey_DataRateLimits, [10*1024*1024, 1] as CFArray)
            
            VTSessionSetProperty(c, kVTCompressionPropertyKey_ColorPrimaries, kCMFormatDescriptionColorPrimaries_ITU_R_2020)
            VTSessionSetProperty(c, kVTCompressionPropertyKey_TransferFunction, kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG)
            VTSessionSetProperty(c, kVTCompressionPropertyKey_YCbCrMatrix, kCMFormatDescriptionYCbCrMatrix_ITU_R_2020)
            VTSessionSetProperty(c, kCMFormatDescriptionExtension_FullRangeVideo, false as CFTypeRef)
            
            
            VTCompressionSessionPrepareToEncodeFrames(c)
            
            self.dumpCMBufferInfo(sampleBuffer)
        }
        
        guard let c = compressionSession else {
            return
        }
        
        guard isCapturing else {
            return
        }
        
        compressionQueue.sync {
            pixelbuffer.lock(.readwrite) {
                let presentationTimestamp = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
                let duration = CMSampleBufferGetOutputDuration(sampleBuffer)
                VTCompressionSessionEncodeFrame(c, pixelbuffer, presentationTimestamp, duration, nil, nil, nil)
            }
        }
    }
    
    func writeCompressedFrame(frame sampleBuffer: CMSampleBuffer) {
        
        guard let writerInput = self.assetWriterInput else {
            return
        }
        
        
        writingQueue.sync {
            defer {
                let result = writerInput.append(sampleBuffer)
                print("append buffer to writer good? \(frameCount):\(result)")
            }
            
            while (!writerInput.isReadyForMoreMediaData) {
                
            }
        }
    }
}

