//
//  ViewController.swift
//  AutoCropPhoto
//
//  Created by Yousef Ayyash on 20/11/2020.
//  Copyright © 2020 Yousef Ayyash. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var capturedImageView: UIImageView!
    @IBOutlet weak var takePhotoBtn: UIButton!
    
    private let captureSession = AVCaptureSession()
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    private var maskLayer = CAShapeLayer()
    private var hintLayer = CATextLayer()
    private var isTapped = false
    
    override func viewDidAppear(_ animated: Bool) {
        self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera_frame_processing_queue"))
        self.captureSession.startRunning()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        self.videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
        self.captureSession.stopRunning()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setCameraInput()
        self.showCameraFeed()
        self.setCameraOutput()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.previewLayer.frame = self.previewView.bounds
    }
    
    private func setCameraInput() {
        guard let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .back).devices.first else {
                fatalError("No back camera device found.")
        }
        let cameraInput = try! AVCaptureDeviceInput(device: device)
        self.captureSession.addInput(cameraInput)
    }
    
    private func showCameraFeed() {
        self.previewLayer.videoGravity = .resizeAspectFill
        self.previewView.layer.addSublayer(self.previewLayer)
        self.previewLayer.frame = self.previewView.frame
    }
    
    private func setCameraOutput() {
        self.videoDataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA)] as [String : Any]
        
        self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
        self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "c"))
        self.captureSession.addOutput(self.videoDataOutput)
        
        guard let connection = self.videoDataOutput.connection(with: AVMediaType.video),
            connection.isVideoOrientationSupported else { return }
        
        connection.videoOrientation = .portrait
    }
    
    func captureOutput(_ output: AVCaptureOutput,didOutput sampleBuffer: CMSampleBuffer,from connection: AVCaptureConnection) {
        guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        self.detectRectangle(in: frame)
    }
    
    private func detectRectangle(in image: CVPixelBuffer) {
        let request = VNDetectRectanglesRequest(completionHandler: { (request: VNRequest?, error: Error?) in
            DispatchQueue.main.async {
                
                
                guard let results = request?.results as? [VNRectangleObservation] else {
                    guard let error = error else { return }
                      print("Error: Rectangle detection failed - Vision request returned an error. \(error.localizedDescription)")
                    return
                }
              
          
                self.removeMask()
                
                
                
                guard let rect = results.first else{
                    self.createLayerHint(in: CGRect(x:self.previewView.bounds.width*0.1 , y: self.previewLayer.bounds.height*0.07, width: self.previewView.bounds.width*0.8 , height: self.previewLayer.bounds.height*0.04), color: UIColor.systemRed.cgColor, text: "Can't Detect Rectangle: Change background Or Adjust Angle")
                    return}
                let diffXTop = Float((rect.topLeft.x - rect.topRight.x))
                let diffYTop = Float((rect.topLeft.y - rect.topRight.y))
                let distanceTop = Float(hypotf(diffXTop,diffYTop))
                let diffXBottom = Float((rect.bottomLeft.x - rect.bottomRight.x))
                let diffYBottom = Float((rect.bottomLeft.y - rect.bottomRight.y))
                let distanceBottom = Float(hypotf(diffXBottom,diffYBottom))
                
                print("distance: \(distanceTop) + \(distanceBottom)")
                
                if( distanceTop < 0.5 ){
                    self.drawBoundingBox(rect: rect, color: UIColor.systemRed.cgColor, text: "Move Closer")
                }
                else if(distanceTop > 0.9 ){
                    self.drawBoundingBox(rect: rect, color: UIColor.systemRed.cgColor, text: "Move Away")
                }
                else if(abs(distanceTop - distanceBottom) > 0.55 ){
                    self.drawBoundingBox(rect: rect, color: UIColor.systemRed.cgColor, text: "Adjust Angle")
                }
                else {
                    self.drawBoundingBox(rect: rect, color: UIColor.systemGreen.cgColor, text: "Hold still and Capture")
                }
                if self.isTapped{
                    self.isTapped = false
                    self.capturedImageView.contentMode = .scaleAspectFit
                    self.capturedImageView.image = self.imageExtraction(rect, from: image)
                }
            }
        })
        
        request.minimumAspectRatio = VNAspectRatio(0.3)
        request.maximumAspectRatio = VNAspectRatio(0.9)
        request.minimumSize = Float(0.3)
        request.quadratureTolerance = VNDegrees(30)
        request.minimumConfidence = 0.6
        request.maximumObservations = 1
        request.usesCPUOnly = false

       
        
        
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
        do {
            try imageRequestHandler.perform([request])
            } catch {
                print("Error: Rectangle detection failed - vision request failed.")
            }
    }
    
    func drawBoundingBox(rect : VNRectangleObservation , color: CGColor, text:String) {
        let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -self.previewLayer.bounds.height)
        let topTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: self.previewView.bounds.width*0.25, y: -self.previewLayer.bounds.height*0.1)
        
        let scale = CGAffineTransform.identity.scaledBy(x: self.previewLayer.bounds.width, y: self.previewLayer.bounds.height)
        let topScale = CGAffineTransform.identity.scaledBy(x: self.previewLayer.bounds.width*0.5, y: self.previewLayer.bounds.height*0.1)
        
        let bounds = rect.boundingBox.applying(scale).applying(transform)
        let top = rect.boundingBox.applying(topScale).applying(topTransform)
        createLayer(in: bounds, color: color)
        createLayerHint(in: top, color: color, text: text)
    }
    
    private func createLayer(in rect: CGRect, color:CGColor) {
        maskLayer = CAShapeLayer()
        maskLayer.frame = rect
        maskLayer.cornerRadius = 0
        maskLayer.opacity = 1
        maskLayer.borderColor = UIColor.systemGreen.cgColor
        maskLayer.borderWidth = 8.0
        previewLayer.insertSublayer(maskLayer, at: 1)
        
    }
    private func createLayerHint(in rect: CGRect, color:CGColor, text: String) {
        hintLayer = CATextLayer()
        hintLayer.fontSize = 15
        hintLayer.frame = rect
        hintLayer.string = text
        hintLayer.foregroundColor = UIColor.systemGray5.cgColor
        hintLayer.backgroundColor = color

        hintLayer.isWrapped = true
        hintLayer.alignmentMode = CATextLayerAlignmentMode.center
        previewLayer.insertSublayer(hintLayer, at: 2)
        
    }
    
    func removeMask() {
        maskLayer.removeFromSuperlayer()
        hintLayer.removeFromSuperlayer()

    }
    
    @IBAction func didTakePhoto(_ sender: UIButton) {
        self.isTapped = true
    }
    
    func imageExtraction(_ observation: VNRectangleObservation, from buffer: CVImageBuffer) -> UIImage {
        var ciImage = CIImage(cvImageBuffer: buffer)
        
        let topLeft = observation.topLeft.scaled(to: ciImage.extent.size)
        let topRight = observation.topRight.scaled(to: ciImage.extent.size)
        let bottomLeft = observation.bottomLeft.scaled(to: ciImage.extent.size)
        let bottomRight = observation.bottomRight.scaled(to: ciImage.extent.size)
        
        ciImage = ciImage.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": CIVector(cgPoint: topLeft),
            "inputTopRight": CIVector(cgPoint: topRight),
            "inputBottomLeft": CIVector(cgPoint: bottomLeft),
            "inputBottomRight": CIVector(cgPoint: bottomRight),
        ])
        
        let context = CIContext()
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        let output = UIImage(cgImage: cgImage!)
        
        return output
    }
    
}

extension CGPoint {
    func scaled(to size: CGSize) -> CGPoint {
        return CGPoint(x: self.x * size.width,
                       y: self.y * size.height)
    }
}
