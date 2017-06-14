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

class Jetpac {
    
    private var network : UnsafeMutableRawPointer?
    private let jpQueue = DispatchQueue(label: "jpQueue", attributes: [])
    
    func load(){
        
        clean()
        jpQueue.sync {
            network = jpcnn_create_network((Bundle.main.path(forResource: "jetpac", ofType: "ntwk")! as NSString).utf8String)
        }
    }
    
    func run(image: CIImage, topLayer: Bool = true)-> [(label: String, prob: Double)]{
        
        var probs = [Double]()
        var labels = [String]()
        
        jpQueue.sync {
            guard let network = network else { return }
            
            let inputEdge = 256
            let frameImage = CIImage(cgImage: resizeImage(image, newWidth: CGFloat(inputEdge), newHeight: CGFloat(inputEdge)).cgImage!)
            
            /*
             let rect = CGRect(x: (image.extent.width-image.extent.height)/2, y: 0, width: image.extent.height, height: image.extent.height)
             let frameImage = image.cropping(to: rect).applying(CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y))
             */
            
            var buffer : CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, Int(frameImage.extent.width), Int(frameImage.extent.height), kCVPixelFormatType_32BGRA, [String(kCVPixelBufferIOSurfacePropertiesKey) : [:]] as CFDictionary, &buffer)
            
            guard let pixelBuffer = buffer else { return }
            CIContext().render(frameImage, to: pixelBuffer)
            
            let sourceRowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
            
            guard let sourceBaseAddr = CVPixelBufferGetBaseAddress(pixelBuffer)?.assumingMemoryBound(to: UInt8.self) else { return }
            
            let cnnInput = jpcnn_create_image_buffer_from_uint8_data(sourceBaseAddr, Int32(width), Int32(height), 4, Int32(sourceRowBytes), 0, 0)
            
            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            
            var values : UnsafeMutablePointer<Float>? = nil
            var length = Int32(0)
            var labels_ : UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>? = nil
            var labelsLength = Int32(0)
            
            jpcnn_classify_image(network, cnnInput, UInt32(JPCNN_RANDOM_SAMPLE), topLayer ? 0 : -2, &values, &length, &labels_, &labelsLength)
            
            jpcnn_destroy_image_buffer(cnnInput)
            
            probs = Array(UnsafeMutableBufferPointer<Float>(start: values, count: Int(length))).map { Double($0) }
            labels = topLayer ? Array(UnsafeMutableBufferPointer<UnsafeMutablePointer<Int8>?>(start: labels_, count: Int(labelsLength))).flatMap { c -> String? in
                if let cc = UnsafePointer<CChar>(c) { return String(utf8String:cc)} else { return nil }}
                : Array(repeating: "", count: Int(length))
            
        }
        return Array(zip(labels,probs))
    }
    
    func run2(image: CIImage)-> [Double] {
        
        return run(image: image, topLayer: false).map { $0.prob }
    }
    
    func clean(){
        jpQueue.sync {
            if let n = network {
                jpcnn_destroy_network(n)
            }
            network = nil
        }
    }
}
