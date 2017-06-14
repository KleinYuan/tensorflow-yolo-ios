
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

//
//  AppDelegate.swift
//  tensorflow-yolo-ios
//
//  Created by Kaiwen Yuan on 2017-06-12.
//  Copyright © 2017 Kaiwen Yuan. All rights reserved.
//

import UIKit

typealias YoloOutput = [(label: String, prob: Double, box: CGRect, object: CIImage)]

class YOLO {
    
    var threshold = 0.5
    private var tfYolo : tfWrap?
    private var coco = false
    private var v2 = false
    
    private let anchors_voc = [1.08, 1.19, 3.42, 4.41, 6.63, 11.38, 9.42, 5.11, 16.62, 10.52]
    private let anchors_coco = [0.738768, 0.874946, 2.42204, 2.65704, 4.30971, 7.04493, 10.246, 4.59428, 12.6868, 11.8741]
    
    typealias YoloBox = (c: Double, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,probs: [Double])
    
    func load(){
        
        clean()
        tfYolo = tfWrap()
        
        tfYolo?.loadModel("tiny-yolo-voc.pb", labels: "voc.txt", memMapped: true, optEnv: true)
        coco = false
        v2 = false
        
        tfYolo?.setInputLayer("input", outputLayer: "output")
        
    }
    
    func run(image: CIImage)-> YoloOutput {
        
        guard let tfYolo = tfYolo else { return [] }
        
        //pre-processing
        let inputEdge = v2 ? 416 : 448
        let input = CIImage(cgImage: resizeImage(image, newWidth: CGFloat(inputEdge), newHeight: CGFloat(inputEdge)).cgImage!)
        
        var buffer : CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, inputEdge, inputEdge, kCVPixelFormatType_32BGRA, [String(kCVPixelBufferIOSurfacePropertiesKey) : [:]] as CFDictionary, &buffer)
        
        if let buffer = buffer {
            CIContext().render(input, to: buffer)
        }
        
        //neural network forward run
        guard let network_output = tfYolo.run(onFrame: buffer) else { return [] }
        
        let output = network_output.flatMap{ ($0 as? NSNumber)?.doubleValue }
        
        //post-processing
        var boxes = postProcessYolo(output: output)
        
        //suppress redundant boxes
        boxes = suppressOverlappingYoloBoxes(boxes, classes: coco ? 80 : 20)
        
        let labels = tfYolo.getLabels().flatMap{ $0 as? String }
        
        return boxes.flatMap { b -> (label: String, prob: Double, box: CGRect, object: CIImage)? in
            //get probabilities per class
            guard let max_prob = b.probs.max() else { return nil }
            guard max_prob>0 else { return nil }
            guard let max_index = b.probs.index(of: max_prob) else { return nil }
            guard max_index<labels.count else { return nil }
            
            let label = labels[max_index]
            guard label != "non_object" else{return nil}
            //convert Yolo boxes to screen
            let frameWidth = image.extent.width
            let frameHeight = image.extent.height
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height
            
            let horizontal = frameWidth/frameHeight > screenWidth/screenHeight
            
            let seenWidth = horizontal ? screenWidth : screenHeight*frameWidth/frameHeight
            let seenHeight = horizontal ? screenWidth*frameHeight/frameWidth : screenHeight
            
            let biasX = horizontal ? 0 : (screenWidth-seenWidth)/2
            let biasY = horizontal ? (screenHeight-seenHeight)/2 : 0
            
            let x = (b.x-b.w/2)*seenWidth + biasX
            let y = (b.y-b.h/2)*seenHeight + biasY
            let w = b.w*seenWidth
            let h = b.h*seenHeight
            let screenRect = CGRect(x: x, y: y, width: w, height: h)
            
            //extract Yolo objects from image
            let xx = (b.x-b.w/2)*frameWidth
            let yy = (b.y-b.h/2)*frameHeight
            let ww = b.w*frameWidth
            let hh = b.h*frameHeight
            
            let rect = CGRect(x: xx, y: yy, width: ww, height: hh)
            
            let object = cropImage(image, to: rect, margin: 0.2*(rect.width<rect.height ? rect.width : rect.height))
            
            return (label, max_prob, screenRect, object)
        }
    }
    
    func postProcessYolo(output:[Double])-> [YoloBox] {
        
        return v2 ? postProcessYoloV2(output: output) : postProcessYoloV1(output: output)
    }
    
    func postProcessYoloV1(output: [Double]) -> [YoloBox] {
        
        let S = 7
        let SS = S*S
        let B = coco ? 3 : 2
        let C = coco ? 80 : 20
        
        let prob_size = SS*C
        let conf_size = SS*B
        
        let probs1 = Array(output.prefix(prob_size))
        let confs1 = Array(output[prob_size..<prob_size+conf_size])
        let cords1 = Array(output[prob_size+conf_size..<output.count])
        
        //reshape!
        
        //zeros in the right dimensions
        var probs = Tensor([SS,C]) as! [[Double]]
        var confs = Tensor([SS,B]) as! [[Double]]
        var cords = Tensor([SS,B,4]) as! [[[Double]]]
        //var cords = [[[Double]]](repeating:[[Double]](repeating: [Double](repeating: 0, count: 4), count: B), count: SS)
        
        //fill in values
        var i = 0
        for ss in 0..<probs.count {
            for c in 0..<probs[ss].count {
                probs[ss][c] = probs1[i]
                i += 1
            }
        }
        
        i = 0
        for ss in 0..<confs.count {
            for b in 0..<confs[ss].count {
                confs[ss][b] = confs1[i]
                i += 1
            }
        }
        
        i = 0
        for ss in 0..<cords.count {
            for b in 0..<cords[ss].count {
                for g in 0..<cords[ss][b].count {
                    cords[ss][b][g] = cords1[i]
                    i += 1
                }
            }
        }
        
        //evaluate boxes
        
        var boxes = [YoloBox]()
        for grid in 0..<SS {
            for b in 0..<B{
                
                //The (x, y) coordinates represent the center of the box relative to the bounds of the grid cell. The width and height are predicted relative to the whole image.
                
                let biasX = Double(grid%S)
                let biasY = floor(Double(grid)/Double(S))
                
                let c = confs[grid][b]
                let x = CGFloat((cords[grid][b][0] + biasX)/Double(S))
                let y = CGFloat((cords[grid][b][1] + biasY)/Double(S))
                let w = CGFloat(pow(cords[grid][b][2],2))
                let h = CGFloat(pow(cords[grid][b][3],2))
                
                let probs = Array(0..<C).map { i in c * probs[grid][i]>self.threshold ? c * probs[grid][i] : 0 }//apply threshold
                
                if probs.contains(where: {$0>0}) {
                    boxes.append((c, x, y, w, h, probs ))
                }
            }
        }
        
        return boxes
        
    }
    
    func postProcessYoloV2(output: [Double]) -> [YoloBox] {
        
        let B = 5
        let W = 13
        let H = 13
        
        let R = output.count/(W*H*B)
        
        var values = Tensor([H,W,B,R]) as! [[[[Double]]]]
        
        var i = 0
        for h in 0..<values.count {
            for w in 0..<values[h].count {
                for b in 0..<values[h][w].count {
                    for r in 0..<values[h][w][b].count {
                        values[h][w][b][r] = output[i]
                        i += 1
                    }
                }
            }
        }
        
        //print("Shape", values.count, values[0].count, values[0][0].count, values[0][0][0].count)
        
        //evaluate boxes
        var boxes = [YoloBox]()
        let anchors = coco ? anchors_coco : anchors_voc
        
        for row in 0..<H {
            for col in 0..<W {
                for b in 0..<B {
                    
                    var x = values[row][col][b][0]
                    var y = values[row][col][b][1]
                    var w = values[row][col][b][2]
                    var h = values[row][col][b][3]
                    var c = values[row][col][b][4]
                    
                    c = expit(c)
                    x = (Double(col)+expit(x))/13
                    y = (Double(row)+expit(y))/13
                    w = pow(M_E, w)*anchors[2*b+0]/13
                    h = pow(M_E, h)*anchors[2*b+1]/13
                    
                    let classes = Array(values[row][col][b][5..<R])
                    
                    let probs = softmax(classes).map { $0*c>self.threshold ? $0*c : 0 }//apply threshold
                    
                    if probs.contains(where: {$0>0}) {
                        boxes.append((c,CGFloat(x),CGFloat(y),CGFloat(w),CGFloat(h),probs))
                    }
                    
                }
            }
        }
        return boxes
        
    }
    
    func suppressOverlappingYoloBoxes(_ boxes:[YoloBox], classes: Int)-> [YoloBox] {
        
        var boxes = boxes
        
        for c in 0..<classes { //for each class
            
            boxes.sort{ a, b -> Bool in a.probs[c] < b.probs[c] }
            
            for i in 0..<boxes.count {
                
                let b = boxes[i]
                if b.probs[c] == 0 { continue }
                
                for j in i+1..<boxes.count {
                    
                    let b2 = boxes[j]
                    let rect1 = CGRect(x: b.x, y: b.y, width: b.w, height: b.h)
                    let rect2 = CGRect(x: b2.x, y: b2.y, width: b2.w, height: b2.h)
                    let intersection = boxIntersection(a: rect1, b: rect2)
                    
                    let area2 = b2.w*b2.h
                    
                    let apart = intersection/area2
                    
                    if apart >= 0.5 {//suppress with over %50 overlap
                        if b.probs[c] > b2.probs[c] {
                            
                            var jprobs = b2.probs
                            jprobs[c] = 0
                            boxes[j] = (b2.c, b2.x, b2.y, b2.w, b2.h, jprobs)
                            
                        } else {
                            var iprobs = b.probs
                            iprobs[c] = 0
                            boxes[i] = (b.c, b.x, b.y, b.w, b.h, iprobs)
                        }
                    }
                }
            }
            
        }
        
        return boxes
    }
    
    func Tensor(_ dim: [Int]) -> [Any] {
        
        guard dim.count > 0 else { return [] }
        var tensor = [Any]()
        
        tensor = [Double](repeating:0,count: dim.last!)
        
        guard dim.count>1 else { return tensor }
        for d in (0...dim.count-2).reversed() {
            tensor = [Any](repeating: tensor,count:dim[d])
        }
        
        return tensor
    }
    
    func boxIntersection(a: CGRect, b: CGRect)-> CGFloat{
        
        func overlap (x1: CGFloat, w1: CGFloat, x2: CGFloat, w2: CGFloat)-> CGFloat{
            
            let l1 = x1 - w1/2
            let l2 = x2 - w2/2
            let left = max(l1,l2)
            
            let r1 = x1 + w1/2
            let r2 = x2 + w2/2
            let right = min(r1,r2)
            
            return right - left
        }
        
        let w = overlap(x1: a.origin.x, w1: a.width, x2: b.origin.x, w2: b.width)
        let h = overlap(x1: a.origin.y, w1: a.height, x2: b.origin.y, w2: b.height)
        
        if w<0 || h<0 { return 0 }
        
        let result = w*h
        
        
        return result
    }
    
    func expit(_ x: Double)-> Double {
        
        let result = Double(1)/Double(1+pow(M_E, -x))
        
        return result
        
    }
    
    func softmax(_ X: [Double])-> [Double] {
        
        guard let max = X.max() else { return [] }
        
        var result = X.map { x in pow(M_E, x-max) }
        
        let sum = result.reduce(0, +)
        
        result = result.map { $0/sum }
        
        return result
        
    }
    
    func clean() {
        tfYolo?.clean()
        tfYolo = nil
    }
    
}
