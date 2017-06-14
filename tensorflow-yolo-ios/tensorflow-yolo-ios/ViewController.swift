//
//  ViewController.swift
//  tensorflow-yolo-ios
//
//  Created by Kaiwen Yuan on 2017-06-12.
//  Copyright © 2017 Kaiwen Yuan. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    var results = UITextView()
    var boxesView = UIView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCam()
        
        async {
            self.loadYoloModel()
            frameProcessing = { frame in
                self.detectYoloObjects(frameImage: frame)
            }
        }
        setResultDisplay()
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func setResultDisplay(){
        self.results.frame = CGRect(x: 20, y: 20, width: self.view.frame.width/2, height: 60)
        self.results.textColor = UIColor.green
        self.results.backgroundColor = UIColor.clear
        self.view.addSubview(self.results)
        self.view.bringSubview(toFront: self.results)
        
        self.boxesView.frame = self.view.frame
        self.boxesView.backgroundColor = UIColor.clear
        self.view.addSubview(boxesView)
        self.view.bringSubview(toFront: self.boxesView)
        
        self.view.layoutSubviews()
    }
    
    
}

//MARK: Jetpac
let jpac = Jetpac()

//MARK: YOLO
let yolo = YOLO()
var yoloThreshold = 0.25
var detectedObjects : YoloOutput = []
var detectedResults = [[String]]()


extension ViewController {
    
    func loadYoloModel() {
        
        yolo.load()
        jpac.load()
    }
    
    func detectYoloObjects(frameImage:CIImage){
        
        yolo.threshold = yoloThreshold
        detectedObjects = yolo.run(image: frameImage)
        
        print("")
        print(detectedObjects.count, "boxes")
        /*
         detectedObjects[0].box.origin.x
         detectedObjects[0].box.origin.y
         detectedObjects[0].box.size.width
         detectedObjects[0].box.size.height
         */
        detectedObjects
            .forEach {
                print($0.label, $0.prob, $0.box);
                detectedResults.append(["\($0.label)", "\($0.prob)", "\($0.box)"])
        }
        DispatchQueue.main.sync() {
            
            self.results.text = ""
            self.cleanView(someView: self.boxesView)
            if detectedObjects.isEmpty == false{
                let numOfObjects = detectedObjects.count
                print("\(numOfObjects) Objects is/are detected!")
                for i in 0..<numOfObjects{
                    
                    self.results.text.append( "\(i) : \(detectedObjects[i].label) \n")
                    let box = detectedObjects[i].box
                    let plotView = PlotView(frame: box)
                    plotView.backgroundColor = UIColor.clear
                    plotView.draw(CGRect(x: box.origin.x, y: box.origin.y, width: box.size.width, height: box.size.height))
                    self.boxesView.addSubview(plotView)
                    
                }
            }
        }
        
    }
    
    func cleanView(someView: UIView){
        for childView in someView.subviews{
            childView.removeFromSuperview()
        }
    }
    
    
}

public class PlotView: UIView
{
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ frame: CGRect)
    {
        let context = UIGraphicsGetCurrentContext()
        context?.setLineWidth(4.0)
        context?.setStrokeColor(UIColor.blue.cgColor)
        print("frame: \(frame)")
        context?.addRect(frame)
        context?.strokePath()
    }
}
