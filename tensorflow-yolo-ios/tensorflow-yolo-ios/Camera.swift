//
//    The MIT License (MIT)
//
//    Copyright (c) 2016 ID Labs L.L.C.
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.
//

import UIKit
import AVFoundation
import Photos

private var CapturingStillImageContext = UnsafeMutableRawPointer.allocate(bytes: 1, alignedTo: 128)//allocate(capacity: 1)
private var SessionRunningContext = UnsafeMutableRawPointer.allocate(bytes: 1, alignedTo: 128)

private var cameraUnavailableLabel: UILabel!
private var resumeButton: UIButton!

// Session management
private var sessionQueue: DispatchQueue!
private var session: AVCaptureSession!
private var videoDeviceInput: AVCaptureDeviceInput!
private var stillImageOutput: AVCapturePhotoOutput!//AVCaptureStillImageOutput!
private var videoDataOutput: AVCaptureVideoDataOutput!

private var frontCam = false

enum AVCamSetupResult: Int {
    case success
    case cameraNotAuthorized
    case sessionConfigurationFailed
}

// Utils
private var setupResult: AVCamSetupResult = .success
private var sessionRunning = false
private var backgroundRecordingID: UIBackgroundTaskIdentifier = 0

private var framesQueue : DispatchQueue!
private var dataQueueSuspended = false

var sourcePixelFormat = OSType()

private var photoSingleton = singleton_handle()
private var photoCaptureCompletion : ((Data)->Void)?
private var end_singleton: ((Void)->Void)?

private var worldView = WorldView()

var frameProcessing: ((CIImage)->Void)?

extension ViewController : AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    
    func setupCam() {
        
        //Cam-related UI elements
        do {
            worldView = WorldView(frame: view.bounds)
            worldView.backgroundColor = UIColor.black
            view.addSubview(worldView)
            view.sendSubview(toBack: worldView)
            
            resumeButton = UIButton(frame: CGRect(origin: worldView.center, size: CGSize(width: 150, height: 50)))
            resumeButton .setTitle("Resume", for: UIControlState())
            resumeButton .setTitleColor(UIColor.white, for: UIControlState())
            resumeButton.backgroundColor = UIColor.lightGray.withAlphaComponent(0.5)
            resumeButton .addTarget(self, action: #selector(ViewController.resumeInterruptedSession(_:)), for: .touchUpInside)
            resumeButton.center = worldView.center
            resumeButton.isHidden = true
            worldView .addSubview(resumeButton)
            
            cameraUnavailableLabel = UILabel(frame: CGRect(origin: worldView.center, size: CGSize(width: 200, height: 50)))
            cameraUnavailableLabel.text = "Camera Unavailable"
            cameraUnavailableLabel.textColor = UIColor.white
            cameraUnavailableLabel.textAlignment = .center
            cameraUnavailableLabel.backgroundColor = UIColor.lightGray.withAlphaComponent(0.5)
            cameraUnavailableLabel.center = worldView.center
            cameraUnavailableLabel.isHidden = true
            worldView .addSubview(cameraUnavailableLabel)
        }
        
        // create AVCaptureSession
        session = AVCaptureSession()
        session.sessionPreset = AVCaptureSessionPresetHigh
        
        // setup the world view
        worldView.session = session
        
        // communicate with the session and other session objects on this queue
        sessionQueue = DispatchQueue(label: "session queue", attributes: [])
        framesQueue = DispatchQueue(label: "framesQueue", attributes: [])
        
        setupResult = .success
        
        // check video authorization status. Video access is required and audio access is optional
        // if audio access is denied, audio is not recorded during movie recording
        switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) {
            
        case .authorized:
            
            break
            
        case .notDetermined:
            // the user has not yet been presented with the option to grant video access.
            // we suspend the session queue to delay session setup until the access request has completed to avoid
            // asking the user for audio access if video access is denied.
            // note that audio access will be implicitly requested when we create an AVCaptureDeviceInput for audio during session setup
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo) { granted in
                if !granted {
                    setupResult = .cameraNotAuthorized
                }
                sessionQueue.resume()
            }
        default:
            // the user has previously denied access
            setupResult = .cameraNotAuthorized
        }
        
        guard setupResult == .success else { return }
        
        backgroundRecordingID = UIBackgroundTaskInvalid
        
        guard let camera =  ViewController.deviceWithMediaType(AVMediaTypeVideo, preferringPosition: frontCam ? .front : .back) else { return }
        let vidInput: AVCaptureDeviceInput!
        do {
            
            vidInput = try AVCaptureDeviceInput(device: camera)
        } catch let error as NSError {
            vidInput = nil
            NSLog("Could not create video device input: %@", error)
        } catch _ {
            fatalError()
        }
        
        session.beginConfiguration()
        
        if session.canAddInput(vidInput) {
            session.addInput(vidInput)
            videoDeviceInput = vidInput
            
            DispatchQueue.main.async{
                let statusBarOrientation = UIApplication.shared.statusBarOrientation
                var initialVideoOrientation = AVCaptureVideoOrientation.portrait
                if statusBarOrientation != .unknown {
                    initialVideoOrientation = AVCaptureVideoOrientation(rawValue: statusBarOrientation.rawValue)!
                }
                
                let previewLayer = worldView.layer as! AVCaptureVideoPreviewLayer
                previewLayer.connection.videoOrientation = initialVideoOrientation
                previewLayer.videoGravity = AVLayerVideoGravityResizeAspect
                
            }
        } else {
            NSLog("Could not add video device input to the session")
            setupResult = .sessionConfigurationFailed
        }
        
        //videoData
        videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
        //NSDictionary(object: Int(kCVPixelFormatType_32BGRA), forKey: kCVPixelBufferPixelFormatTypeKey as String) as! [NSObject : AnyObject]
        
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        framesQueue.suspend(); dataQueueSuspended = true
        videoDataOutput .setSampleBufferDelegate(self, queue:framesQueue )
        
        if session .canAddOutput(videoDataOutput) { session .addOutput(videoDataOutput) }
        
        //orient frames to initial application orientation
        let statusBarOrientation = UIApplication.shared.statusBarOrientation
        if statusBarOrientation != .unknown {
            videoDataOutput.connection(withMediaType: AVMediaTypeVideo).videoOrientation = AVCaptureVideoOrientation(rawValue: statusBarOrientation.rawValue)!
        }
        
        //Still Image
        let still = AVCapturePhotoOutput()
        if session.canAddOutput(still) {
            //still.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
            session.addOutput(still)
            stillImageOutput = still
        } else {
            NSLog("Could not add still image output to the session")
            setupResult = .sessionConfigurationFailed
            
        }
        
        session.commitConfiguration()
        
        //start cam
        if setupResult == .success {
            session.startRunning()//blocking call
            sessionRunning = session.isRunning
            resumeFrames()
        }
        
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let frameImage = CIImage(cvPixelBuffer: buffer)
        
        frameProcessing?(frameImage)
        
    }
    
    func checkCam() -> AVCamSetupResult {
        
        sessionQueue.sync {
            switch setupResult {
            case .success:
                // only setupt observers and start the session running if setup succeeded
                
                self.addObservers()
                //session.startRunning()
                //sessionRunning = session.running
                
                break
                
            case .cameraNotAuthorized:
                DispatchQueue.main.async {
                    let message = NSLocalizedString("App doesn't have permission to use the camera, please change privacy settings", comment: "The user has denied access to the camera")
                    let alertController = UIAlertController(title: "Permission for neOn", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    // provide quick access to Settings.
                    let settingsAction = UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"), style: .default) { action in
                        //UIApplication.shared.openURL(URL(string: UIApplicationOpenSettingsURLString)!)
                        UIApplication.shared.open(URL(string: UIApplicationOpenSettingsURLString)!, options: [:], completionHandler: nil)
                    }
                    alertController.addAction(settingsAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            case .sessionConfigurationFailed:
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to capture media", comment: "Something went wrong during capture session configuration")
                    let alertController = UIAlertController(title: "Permission for neOn", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
        
        return setupResult
    }
    
    func stopCam() {
        
        sessionQueue.async {
            if setupResult == .success {
                session.stopRunning()
                sessionRunning = false
                //self .removeObservers()
            }
        }
        
    }
    
    func startCam() {
        
        sessionQueue.async {
            
            if setupResult == .success {
                self.addObservers()
                session.startRunning()
                sessionRunning = session.isRunning
            }
            
        }
    }
    
    func toggleCam() {
        
        suspendFrames()
        stopCam()
        
        frontCam = !frontCam
        setupCam()
        resumeFrames()
        
    }
    
    func resumeFrames() {
        
        sessionQueue.async{
            if dataQueueSuspended { framesQueue.resume() }
            dataQueueSuspended = false
        }
        
    }
    
    func suspendFrames() {
        
        sessionQueue.async {
            if !dataQueueSuspended { framesQueue.suspend() }
            dataQueueSuspended = true
        }
        
    }
    
    func orientCam() {
        
        let deviceOrientation = UIDevice.current.orientation
        if UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation) {
            let previewLayer = worldView.layer as! AVCaptureVideoPreviewLayer
            previewLayer.connection.videoOrientation = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue)!
            videoDataOutput.connection(withMediaType: AVMediaTypeVideo).videoOrientation = AVCaptureVideoOrientation(rawValue: deviceOrientation.rawValue)!
        }
        
    }
    
    func stillImageCapture(completion: @escaping (Data)->Void) {
        
        async_singleton_wait(photoSingleton) { end in
            
            end_singleton = end
            
            let connection = stillImageOutput.connection(withMediaType: AVMediaTypeVideo)
            let previewLayer = worldView.layer as! AVCaptureVideoPreviewLayer
            
            // Update the orientation on the still image output video connection before capturing.
            connection?.videoOrientation = previewLayer.connection.videoOrientation
            
            // Flash set to Auto for Still Capture.
            //Surface.setFlashMode(AVCaptureFlashMode.auto, forDevice: videoDeviceInput.device)
            
            photoCaptureCompletion = completion
            
            // Capture a still image.
            let settings = AVCapturePhotoSettings(format: nil)//control flash and more
            stillImageOutput.capturePhoto(with: settings, delegate: self)
            
            /*stillImageOutput.captureStillImageAsynchronously(from: connection) { (imageDataSampleBuffer, error) -> Void in
             
             if imageDataSampleBuffer != nil {
             // The sample buffer is not retained. Create image data before saving the still image to the photo library asynchronously.
             let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
             
             handler(imageData!)
             
             } else {
             NSLog("Could not capture still image: %@", error)
             }
             }*/
            
        }
        
    }
    
    func capture(_ captureOutput: AVCapturePhotoOutput, didFinishProcessingPhotoSampleBuffer photoSampleBuffer: CMSampleBuffer?, previewPhotoSampleBuffer: CMSampleBuffer?, resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Error?) {
        
        guard let photoSampleBuffer = photoSampleBuffer else {
            print("Could not capture still image")
            return
        }
        
        guard let data = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: photoSampleBuffer, previewPhotoSampleBuffer: previewPhotoSampleBuffer) else { return }
        
        photoCaptureCompletion?(data)
        end_singleton?()
        end_singleton = nil
        
    }
    
    //MARK: KVO and Notifications
    
    fileprivate func addObservers() {
        session.addObserver(self, forKeyPath: "running", options: NSKeyValueObservingOptions.new, context: SessionRunningContext)
        stillImageOutput.addObserver(self, forKeyPath: "capturingStillImage", options:NSKeyValueObservingOptions.new, context: CapturingStillImageContext)
        
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.subjectAreaDidChange(_:)), name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.sessionRuntimeError(_:)), name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)
        // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
        // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
        // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
        // interruption reasons.
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.sessionWasInterrupted(_:)), name: NSNotification.Name.AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.sessionInterruptionEnded(_:)), name: NSNotification.Name.AVCaptureSessionInterruptionEnded, object: session)
    }
    
    fileprivate func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        session.removeObserver(self, forKeyPath: "running", context: SessionRunningContext)
        stillImageOutput.removeObserver(self, forKeyPath: "capturingStillImage", context: CapturingStillImageContext)
    }
    
    /*override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
     switch context {
     
     case CapturingStillImageContext:
     
     let isCapturingStillImage = change![NSKeyValueChangeKey.newKey]! as! Bool
     
     if isCapturingStillImage {
     DispatchQueue.main.async {
     self.worldView.layer.opacity = 0.0
     UIView.animate(withDuration: 0.25, animations: {
     self.worldView.layer.opacity = 1.0
     })
     }
     }
     case SessionRunningContext:
     //let isSessionRunning = change![NSKeyValueChangeNewKey]! as! Bool
     
     DispatchQueue.main.async {
     //self.snapGesture.enabled = isSessionRunning
     //self.quickSnapGesture.enabled = isSessionRunning
     }
     default:
     super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
     }
     }*/
    
    func subjectAreaDidChange(_ notification: Notification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        self.focusWithMode(.autoFocus, exposeWithMode: .autoExpose, atDevicePoint: devicePoint, monitorSubjectAreaChange: true)
    }
    
    func sessionRuntimeError(_ notification: Notification) {
        let error = (notification as NSNotification).userInfo![AVCaptureSessionErrorKey]! as! NSError
        NSLog("Capture session runtime error: %@", error)
        
        // Automatically try to restart the session running if media services were reset and the last start running succeeded.
        // Otherwise, enable the user to try to resume the session running.
        if error.code == AVError.Code.mediaServicesWereReset.rawValue {
            sessionQueue.async {
                if sessionRunning {
                    session.startRunning()
                    sessionRunning = session.isRunning
                } else {
                    DispatchQueue.main.async {
                        resumeButton.isHidden = false
                    }
                }
            }
        } else {
            resumeButton.isHidden = false
        }
    }
    
    func sessionWasInterrupted(_ notification: Notification) {
        // In some scenarios we want to enable the user to resume the session running.
        // For example, if music playback is initiated via control center while using AVCam,
        // then the user can let AVCam resume the session running, which will stop music playback.
        // Note that stopping music playback in control center will not automatically resume the session running.
        // Also note that it is not always possible to resume, see -[resumeInterruptedSession:].
        var showResumeButton = false
        
        // In iOS 9 and later, the userInfo dictionary contains information on why the session was interrupted.
        let reason = (notification as NSNotification).userInfo![AVCaptureSessionInterruptionReasonKey]! as! Int
        NSLog("Capture session was interrupted with reason %ld", reason)
        
        if reason == AVCaptureSessionInterruptionReason.audioDeviceInUseByAnotherClient.rawValue ||
            reason == AVCaptureSessionInterruptionReason.videoDeviceInUseByAnotherClient.rawValue {
            showResumeButton = true
        } else if reason == AVCaptureSessionInterruptionReason.videoDeviceNotAvailableWithMultipleForegroundApps.rawValue {
            // Simply fade-in a label to inform the user that the camera is unavailable.
            cameraUnavailableLabel.isHidden = false
            cameraUnavailableLabel.alpha = 0.0
            UIView.animate(withDuration: 0.25, animations: {
                cameraUnavailableLabel.alpha = 1.0
            })
        }
        
        /*if #available(iOS 9.0, *) {
         } else {
         NSLog("Capture session was interrupted")
         showResumeButton = (UIApplication.sharedApplication().applicationState == UIApplicationState.Inactive)
         }*/
        
        if showResumeButton {
            // Simply fade-in a button to enable the user to try to resume the session running.
            resumeButton.isHidden = false
            resumeButton.alpha = 0.0
            UIView.animate(withDuration: 0.25, animations: {
                resumeButton.alpha = 1.0
            })
        }
    }
    
    func sessionInterruptionEnded(_ notification: Notification) {
        NSLog("Capture session interruption ended")
        
        if !resumeButton.isHidden {
            UIView.animate(withDuration: 0.25, animations: {
                resumeButton.alpha = 0.0
            }, completion: {finished in
                resumeButton.isHidden = true
            })
        }
        if !cameraUnavailableLabel.isHidden {
            UIView.animate(withDuration: 0.25, animations: {
                cameraUnavailableLabel.alpha = 0.0
            }, completion: {finished in
                cameraUnavailableLabel.isHidden = true
            })
        }
    }
    
    //MARK: Actions
    
    func resumeInterruptedSession(_ sender: AnyObject) {
        
        sessionQueue.async {
            // The session might fail to start running, e.g., if a phone or FaceTime call is still using audio or video.
            // A failure to start the session running will be communicated via a session runtime error notification.
            // To avoid repeatedly failing to start the session running, we only try to restart the session running in the
            // session runtime error handler if we aren't trying to resume the session running.
            session.startRunning()
            sessionRunning = session.isRunning
            if !session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: UIAlertControllerStyle.alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: UIAlertActionStyle.cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            } else {
                DispatchQueue.main.async {
                    resumeButton.isHidden = true
                }
            }
        }
    }
    
    
    @IBAction func focusAndExposeTap(_ gestureRecognizer: UIGestureRecognizer) {
        let devicePoint = (worldView.layer as! AVCaptureVideoPreviewLayer).captureDevicePointOfInterest(for: gestureRecognizer.location(in: gestureRecognizer.view))
        self.focusWithMode(AVCaptureFocusMode.autoFocus, exposeWithMode: AVCaptureExposureMode.autoExpose, atDevicePoint: devicePoint, monitorSubjectAreaChange: true)
        
    }
    
    //MARK: Device Configuration
    func focusWithMode(_ focusMode: AVCaptureFocusMode, exposeWithMode exposureMode: AVCaptureExposureMode, atDevicePoint point:CGPoint, monitorSubjectAreaChange: Bool) {
        sessionQueue.async {
            let device = videoDeviceInput.device
            do {
                try device?.lockForConfiguration()
                defer {device?.unlockForConfiguration()}
                // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
                // Call -set(Focus/Exposure)Mode: to apply the new point of interest.
                if (device?.isFocusPointOfInterestSupported)! && (device?.isFocusModeSupported(focusMode))! {
                    device?.focusPointOfInterest = point
                    device?.focusMode = focusMode
                }
                
                if (device?.isExposurePointOfInterestSupported)! && (device?.isExposureModeSupported(exposureMode))! {
                    device?.exposurePointOfInterest = point
                    device?.exposureMode = exposureMode
                }
                
                device?.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
            } catch let error as NSError {
                NSLog("Could not lock device for configuration: %@", error)
            } catch _ {}
        }
    }
    
    /*class func setFlashMode(_ flashMode: AVCaptureFlashMode, forDevice device: AVCaptureDevice) {
     if device.hasFlash && device.isFlashModeSupported(flashMode) {
     do {
     try device.lockForConfiguration()
     defer {device.unlockForConfiguration()}
     device.flashMode = flashMode
     } catch let error as NSError {
     NSLog("Could not lock device for configuration: %@", error)
     }
     }
     }*/
    
    class func deviceWithMediaType(_ mediaType: String, preferringPosition position: AVCaptureDevicePosition) -> AVCaptureDevice? {
        
        guard let devices =  AVCaptureDeviceDiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: mediaType, position: position).devices else { return nil }
        
        //let devices = AVCaptureDevice.devices(withMediaType: mediaType)
        guard var captureDevice = devices.first else { return nil }
        
        for device in devices as [AVCaptureDevice] {
            if device.position == position {
                captureDevice = device
                break
            }
        }
        
        return captureDevice
    }
    
    
    //MARK: - Orientation
    override var shouldAutorotate : Bool {
        return true
    }
    
    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        return .landscape
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        orientCam()
    }
    
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
}

class WorldView: UIView {
    
    override class var layerClass : AnyClass {
        
        return AVCaptureVideoPreviewLayer.self
    }
    
    var session : AVCaptureSession {
        
        get {
            
            let previewLayer = self.layer as! AVCaptureVideoPreviewLayer
            return previewLayer.session
        }
        
        set (session) {
            
            let previewLayer = self.layer as! AVCaptureVideoPreviewLayer
            previewLayer.session = session
            
        }
    }
    
}


