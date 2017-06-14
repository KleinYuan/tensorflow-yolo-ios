//
//  AppDelegate.swift
//  tensorflow-yolo-ios
//
//  Created by Kaiwen Yuan on 2017-06-12.
//  Copyright © 2017 Kaiwen Yuan. All rights reserved.
//

import Foundation
import UIKit
import WebKit

func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l < r
    case (nil, _?):
        return true
    default:
        return false
    }
}

func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let (l?, r?):
        return l > r
    default:
        return rhs < lhs
    }
}


extension Array {
    
    /* Swift 2.0
     
     subscript (safe index: Int) -> Element? {
     
     return indices ~= index ? self[index] : nil
     }*/
    
    func insertForward(_ input: Element) -> (result: Array, removed: Element?) {
        
        let arr = Array<Int>(0..<count)
        
        return (arr.map { i in
            
            i==arr.first ? input : self [i-1]
            
        }, self.last)
    }
    
    func insertBackward(_ input: Element) -> (result: Array, removed: Element?) {
        
        let arr = Array<Int>(0..<count)
        
        return (arr.map { i in
            
            i==arr.last ? input : self[i+1]
            
        }, self.first)
        
    }
    
    func rotateForward() -> Array {
        
        if let insertion = self.last {
            
            return insertForward(insertion).result
        }
        
        return self
        
        
    }
    
    func rotateBackward() -> Array {
        
        if let insertion = self.first {
            return insertBackward(insertion).result
        }
        
        return self
    }
    
    func rotate(_ steps: Int) -> Array {
        
        return Array<Int>(0..<abs(steps)).reduce(self, { (rot, i) -> Array in steps>0 ? rot.rotateForward() : rot.rotateBackward()
        })
        
    }
    
    func rollRotate(_ steps: Int) -> [Array] {
        
        return Array<Int>(0..<abs(steps)).map { i in steps>0 ? self.rotate(i+1) : self.rotate(-i-1)}
    }
    
    func rollRotateInward() -> [Array] {
        
        return rollRotate(count)
        
    }
    
    func rollRotateOutward() -> [Array] {
        
        return rollRotate(-count)
        
    }
    
    
    func rollFlowInward(_ input: Array) -> [(result: Array,removed: Element?)] {
        
        return Array<Int>(0..<input.count).map { i in
            
            Array<Int>(0...i).reduce((self,self.last), { (flow, j) -> (Array,Element?) in
                
                flow.0.insertForward(Array(input.reversed())[j])
            })
            
        }
        
    }
    
    func rollFlowOutward(_ input: Array) -> [(result: Array,removed: Element?)] {
        
        return Array<Int>(0..<input.count).map { i  in
            
            Array<Int>(0...i).reduce((self,self.first), { (flow, j) -> (Array,Element?) in
                
                flow.0.insertBackward(input[j])
            })
        }
        
        
    }
    
    func roll(_ empty :Element) ->[Array] {
        
        return Array<Element>(repeating: empty, count: count).rollFlowOutward(self).map { $0.result }
        
    }
    
    func unroll(_ empty :Element) ->[Array] {
        
        return rollFlowInward(Array<Element>(repeating: empty, count: count)).map { $0.result }
    }
    
    var shuffle: [Element] {
        var elements = self
        for index in indices.dropLast() {
            guard
                case let swapIndex = Int(arc4random_uniform(UInt32(count - index))) + index
                , swapIndex != index else { continue }
            swap(&elements[index], &elements[swapIndex])
        }
        return elements
    }
    
    mutating func shuffled() {
        for index in indices.dropLast() {
            guard
                case let swapIndex = Int(arc4random_uniform(UInt32(count - index))) + index
                , swapIndex != index
                else { continue }
            swap(&self[index], &self[swapIndex])
        }
    }
    
    var chooseOne: Element {
        return self[Int(arc4random_uniform(UInt32(count)))]
    }
    
    func choose(_ n: Int) -> [Element] {
        return Array(shuffle.prefix(n))
    }
    
}

extension CGPoint {
    
    func distanceToPoint(_ p: CGPoint) -> CGFloat {
        
        return sqrt(pow(self.x-p.x, 2) + pow(self.y-p.y, 2))
        
    }
    
    func distanceToPoints(_ pts: Array<CGPoint>) -> Array<CGFloat> {
        
        return pts.map { p in distanceToPoint(p) }
        
    }
    
}

extension CGFloat {
    
    var rotLmt45: CGFloat { // -45..45
        
        var phi = self
        
        if phi<0 {
            while phi<DegToRad(-45) { phi += DegToRad(90) }
        } else if phi>0 {
            while phi>DegToRad(45) { phi -= DegToRad(90) }
        }
        
        return phi
    }
    
    func random()->CGFloat{
        
        return self * CGFloat(Float(arc4random())/Float(UINT32_MAX)) /* 0->1.0 */
    }
    
}

func DegToRad(_ a:CGFloat)->CGFloat {
    
    let b = CGFloat(M_PI) * a/180
    
    return b
}


extension CGAffineTransform {
    
    var rotAngle: CGFloat {
        
        return atan2(b, a)
    }
    
    var hScale: CGFloat {
        
        return sqrt(pow(a, 2)+pow(c, 2))
    }
    
    var vScale: CGFloat {
        
        return sqrt(pow(b, 2)+pow(d, 2))
    }
    
    var contTrans: CGAffineTransform {
        
        //rotate content
        var contTrans = self.inverted()
        
        let leafAngle = rotAngle.rotLmt45
        let contAngle = DegToRad(15)*leafAngle/abs(leafAngle)
        
        if abs(leafAngle)>DegToRad(20) && abs(leafAngle)<DegToRad(40) {
            contTrans = contTrans.rotated(by: contAngle)
        }
        
        //scale content
        let scale = abs(leafAngle)>DegToRad(30) ? CGFloat(1.4) : CGFloat(1.23)
        return contTrans.scaledBy(x: scale, y: scale)
    }
}

protocol PointType {
    
    var x : CGFloat { get }
    var y : CGFloat { get }
    
    func rotateAt(_ pt: PointType, angle: CGFloat) -> PointType
    func quad(_ center: CGPoint) -> Int
    
}
extension CGPoint : PointType {
    
    func rotateAt(_ pt: PointType, angle: CGFloat) -> PointType {
        
        let translateToOrigin = CGAffineTransform(translationX: x, y: y)
        let rotationTransform = CGAffineTransform(rotationAngle: angle);
        let translateBackFromOrigin = translateToOrigin.inverted();
        
        var totalTransform = translateToOrigin.concatenating(rotationTransform);
        totalTransform = totalTransform.concatenating(translateBackFromOrigin);
        
        return self.applying(totalTransform);
    }
    
    
    func quad(_ center: CGPoint) -> Int {
        
        if x > center.x {
            if y < center.y { return 0 } else { return 1 }
        } else {
            if y > center.y { return 2 } else { return 3 }
        }
    }
}

extension Array where Element : PointType {
    
    var center : CGPoint {
        
        guard let st = self.first as? CGPoint else { return CGPoint.zero }
        
        return self.reduce(st) { total,p -> CGPoint in CGPoint(x: (total.x+p.x)*0.5, y: (total.y+p.y)*0.5)}
        
    }
    
}

public func + (left: CGPoint, right: CGPoint) -> CGPoint {
    return CGPoint(x: left.x + right.x, y: left.y + right.y)
}

public func - (left: CGPoint, right: CGPoint) -> CGPoint {
    return CGPoint(x: left.x - right.x, y: left.y - right.y)
}

public func -= (left: inout CGPoint, right: CGPoint) {
    left = left - right
}

public func += (left: inout CGPoint, right: CGPoint) {
    left = left + right
}

public func + (left: CGPoint, right: CGSize) -> CGPoint {
    return CGPoint(x: left.x + right.width, y: left.y + right.height)
}

public func + (left: CGSize, right: CGPoint) -> CGSize {
    return CGSize(width: left.width + right.x, height: left.height + right.y)
}


public func - (left: CGPoint, right: CGSize) -> CGPoint {
    return CGPoint(x: left.x - right.width, y: left.y - right.height)
}

public func - (left: CGSize, right: CGPoint) -> CGSize {
    return CGSize(width: left.width - right.x, height: left.height - right.y)
}


public func *(left: CGFloat, right: CGPoint) -> CGPoint {
    return CGPoint(x: right.x*left, y: right.y*left)
}

public func *(left: CGPoint, right: CGFloat) -> CGPoint {
    return CGPoint(x: left.x*right, y: left.y*right)
}

public func /(left: CGPoint, right: CGFloat) -> CGPoint {
    return CGPoint(x: left.x/right, y: left.y/right)
}


public func *(left: CGFloat, right: CGSize) -> CGSize {
    return CGSize(width: right.width*left, height: right.height*left)
}

public func *(left: CGSize, right: CGFloat) -> CGSize {
    return CGSize(width: left.width*right, height: left.height*right)
}

public func /(left: CGSize, right: CGFloat) -> CGSize {
    return CGSize(width: left.width/right, height: left.height/right)
}


protocol CenterType {
    
    var center : CGPoint { get }
}

extension Array where Element : CenterType {
    
    var center : CGPoint {
        
        return map { $0.center } .center
    }
    
    /*
     func topmostRight() -> Element {
     
     let quad = fourQuadrants(center).filter ({ $0.count>0 }).first!
     
     return quad.reduce(first!) { trE, e in
     
     return e.center.y < trE.center.y ? e : trE
     }
     }
     
     func aggregate(mass mass: Int, from firstElement: Element) -> Array {
     
     guard count > 1 else { return self }
     guard let st = indexOf ({ $0.center == firstElement.center }) else { return self }
     guard count >= mass else  { return self }
     guard mass>0 else { return self }
     
     var head = Array()
     var arr = Array(self)
     
     head .append(arr .removeAtIndex(st))
     
     while arr.count > 0 {
     
     let before = arr.fourQuadrants(center)[0..<head.center.quad(center)]
     let after = arr.fourQuadrants(center)[head.center.quad(center)..<4]
     let quad = (after+before).filter { $0.count>0 }.first!
     
     let dists = Array(head.suffix(mass)).center.distanceToPoints(quad.map {$0.center})
     guard let min = dists .minElement() else { return self }
     guard let i = dists .indexOf(min) else { return self }
     
     let chosen = quad[i]
     arr .removeAtIndex(arr.map({$0.center}).indexOf(chosen.center)!)
     
     head .append(chosen)
     }
     
     return head
     }
     
     func aggregate(mass mass: Int, var auxArray: Array) -> Array {
     
     guard count > 1 else { return self }
     guard count >= mass else  { return self }
     guard mass > 0 else { return self }
     
     guard auxArray.count == count else { return self }
     
     var result = Array()
     var head = Array()
     var arr = Array(self)
     
     //first is the nearest to the aux first
     head .append(auxArray.first!)
     
     while arr.count > 0 {
     
     let before = arr.fourQuadrants(center)[0..<head.center.quad(center)]
     let after = arr.fourQuadrants(center)[head.center.quad(center)..<4]
     let quad = (after+before).filter { $0.count>0 }.first!
     
     let dists = Array(head.suffix(mass*2)).center.distanceToPoints(quad.map {$0.center})
     guard let min = dists .minElement() else { return self }
     guard let i = dists .indexOf(min) else { return self }
     
     let chosen = quad[i]; result .append(chosen);
     arr .removeAtIndex(arr.map({$0.center}).indexOf(chosen.center)!)
     
     head .append(chosen); head .append(auxArray.removeFirst())
     
     }
     
     return result
     
     }
     
     */
    func nearestElementTo(_ extElement: CenterType) -> (CenterType, CGFloat)? {
        
        let targets = Array(self)
        let dists = extElement.center.distanceToPoints(targets.map { $0.center })
        guard let min = dists.min() else { return nil }
        guard let i = dists.index(of: min) else { return nil }
        
        return (targets[i], min)
        
    }
    
    func fourQuadrants(_ center: CGPoint)-> [Array]{
        
        let first = filter { $0.center.x > center.x && $0.center.y < center.y }
        let second = filter { $0.center.x > center.x && $0.center.y > center.y }
        let third = filter { $0.center.x < center.x && $0.center.y > center.y }
        let fourth = filter { $0.center.x < center.x && $0.center.y < center.y }
        
        return [first, second, third, fourth]
    }
}

var activityOverlay: UIView?

protocol GesturePassingView {}

extension UIView {
    
    var edge : CGFloat {
        set { bounds.size = CGSize(width: newValue, height: newValue) }
        get { return min(bounds.size.width, bounds.size.height) }
    }
    
    var imageView: UIImageView?{
        return self.subviews.filter({$0.isKind(of: UIImageView.self)}).first as? UIImageView
    }
    
    var imageViews: [UIImageView]?{
        return self.subviews.filter({$0.isKind(of: UIImageView.self)}).flatMap{ $0 as? UIImageView }
    }
    
    var effectView: UIVisualEffectView?{
        return self.subviews.filter({$0.isKind(of: UIVisualEffectView.self)}).first as? UIVisualEffectView
    }
    
    func setActions(tap: ((UIView)->())?, press:((UIView)->(),duration: Double)?, drag:((UIView)->())?){
        
        clearActions()
        
        if let tapAction = tap {
            
            let tapGest = UITapGestureRecognizer(){ tapAction(self) }
            if let dt = self.doubleTapGesture { tapGest.require(toFail: dt) }
            addGestureRecognizer(tapGest)
        }
        
        if let pressAction = press {
            
            let pressGest = UILongPressGestureRecognizer() { pressAction.0(self) }
            pressGest.minimumPressDuration = pressAction.1//0.2
            addGestureRecognizer(pressGest)
            
            //avoid being overridden by parent press
            if let parentView = superview{
                if let parentPress = parentView.pressGesture {
                    parentPress.require(toFail: pressGest)
                }
            }
        }
        
        if let dragAction = drag {
            
            let panGest = UIPanGestureRecognizer() { dragAction(self) }
            panGest.maximumNumberOfTouches = 1
            addGestureRecognizer(panGest)
            
        }
    }
    
    func setDoubleTapAction(_ action:((UIView)->Void)?){
        if let action = action {
            let gest = UITapGestureRecognizer(){ action(self) }
            gest.numberOfTapsRequired = 2//double tap
            self.tapGesture?.require(toFail: gest)
            
            addGestureRecognizer(gest)
        }
    }
    
    func setDoubleTouchTapAction(_ action:((UIView)->Void)?){
        if let action = action {
            let gest = UITapGestureRecognizer(){ action(self) }
            gest.numberOfTouchesRequired = 2//double touch
            if let dt = self.doubleTapGesture { gest.require(toFail: dt) }
            addGestureRecognizer(gest)
        }
    }
    
    func setActions(tap: ((UIView)->())?, press:((UIView)->(),duration: Double)?, pan:((UIView)->())?,pinch: ((UIView)->())?, edge:((UIView)->())?){
        
        setActions(tap: tap, press: press, drag: pan)
        
        if let pinchAction = pinch {
            let pinchGest = UIPinchGestureRecognizer() { pinchAction(self) }
            addGestureRecognizer(pinchGest)
            
        }
        
        if let edgeAction = edge {
            let edgeRightGest = UIScreenEdgePanGestureRecognizer() { edgeAction(self) }
            edgeRightGest.edges = .right
            addGestureRecognizer(edgeRightGest)
            
            let edgeLeftGest = UIScreenEdgePanGestureRecognizer() { edgeAction(self) }
            edgeLeftGest.edges = .left
            addGestureRecognizer(edgeLeftGest)
        }
        
        if let eg = edgeGestures {
            for g in eg {
                panGesture?.require(toFail: g)
            }
        }
        
    }
    
    func setActions(tap: (()->())?, press:(()->(),duration: Double)?, drag:(()->())?){
        
        var press2:((UIView)->(),duration: Double)?
        if let p = press {
            press2 = ({ (UIView)->() in p.0() }, p.duration)
        }
        
        setActions(tap: { (v:UIView)->() in tap?()}, press: press2, drag: {(v:UIView)->() in drag?()})
        
    }
    
    func setActions(tap: (()->())?, press:(()->(),duration: Double)?, pan:(()->())?,pinch: (()->())?, edge:(()->())?){
        
        var press2:((UIView)->(),duration: Double)?
        if let p = press {
            press2 = ({ (UIView)->() in p.0() }, p.duration)
        }
        
        setActions(tap: { (v:UIView)->() in tap?()}, press: press2, pan: {(v:UIView)->() in pan?() }, pinch: { (v:UIView)->() in pinch?() }, edge:{ (v: UIView)->() in edge?() } )
    }
    
    func clearActions(){
        if let gs = gestureRecognizers {
            for g in gs {
                removeGestureRecognizer(g)
            }
        }
    }
    
    func requiresActionsToFail(_ view: UIView?){
        
        guard let view = view else { return }
        
        if let gestures2 = view.gestureRecognizers{
            if let gestures1 = gestureRecognizers {
                for g2 in gestures2 {
                    for g1 in gestures1{
                        g1.require(toFail: g2)
                    }
                }
            }
        }
    }
    
    var tapGesture: UITapGestureRecognizer? {
        return self.gestureRecognizers?.filter({ $0 is UITapGestureRecognizer }).filter({ ($0 as? UITapGestureRecognizer)?.numberOfTapsRequired==1 }).first as? UITapGestureRecognizer
        
    }
    
    var doubleTapGesture: UITapGestureRecognizer?{
        return self.gestureRecognizers?.filter({ $0 is UITapGestureRecognizer }).filter({ ($0 as? UITapGestureRecognizer)?.numberOfTapsRequired==2 }).first as? UITapGestureRecognizer
    }
    
    var doubleTouchTapGesture: UITapGestureRecognizer?{
        return self.gestureRecognizers?.filter({ $0 is UITapGestureRecognizer }).filter({ ($0 as? UITapGestureRecognizer)?.numberOfTouchesRequired==2 }).first as? UITapGestureRecognizer
    }
    
    var pressGesture: UILongPressGestureRecognizer? {
        return self.gestureRecognizers?.filter({ $0 is UILongPressGestureRecognizer }).first as? UILongPressGestureRecognizer
    }
    
    var panGesture: UIPanGestureRecognizer? {
        return self.gestureRecognizers?.filter({ $0 is UIPanGestureRecognizer }).first as? UIPanGestureRecognizer
    }
    
    var pinchGesture: UIPinchGestureRecognizer? {
        return self.gestureRecognizers?.filter({ $0 is UIPinchGestureRecognizer }).first as? UIPinchGestureRecognizer
        
    }
    
    var edgeGestures: [UIScreenEdgePanGestureRecognizer]?{
        return self.gestureRecognizers?.filter({ $0 is UIScreenEdgePanGestureRecognizer }) as? [UIScreenEdgePanGestureRecognizer]
    }
    
    func addActivityIndicatorOverlay(_ completion:((_ remove: @escaping(Void)->Void)->Void)?) {
        
        let ser = serial_handle()
        
        
        
        async_serial_main_wait(ser){ next in
            
            let actView = UIView(frame: self.bounds)
            actView.backgroundColor = UIColor.black
            actView.alpha = 0.5
            
            let indict = UIActivityIndicatorView(frame: CGRect(origin: CGPoint.zero, size: actView.bounds.size/7))
            indict.center = actView.center; indict.activityIndicatorViewStyle = .whiteLarge
            actView .addSubview(indict)
            indict .startAnimating()
            
            var removeTask:((Void)->Void)? = { next() }
            self.smoothAddSubview(actView, duration: 0.5) { completion?({oneShot(&removeTask)}) }
            
            activityOverlay = actView
        }
        
        async_serial_main(ser){
            self.removeActivityIndicatorOverlay()
        }
    }
    
    func removeActivityIndicatorOverlay() {
        async_main {
            activityOverlay? .removeFromSuperview()
            activityOverlay = nil
        }
    }
    
    
    func haltInteraction() {
        
        isUserInteractionEnabled = false
        //print("halt")
        
    }
    
    func resumeInteraction() {
        
        isUserInteractionEnabled = true
        //print("resume")
    }
    
    func flash(){
        
        flash(color: UIColor.white)
    }
    
    func flash(color: UIColor) {
        
        let flashView = UIView(frame: CGRect(origin: CGPoint.zero, size: self.bounds.size))
        flashView.backgroundColor = color
        flashView.alpha = 0.5
        addSubview(flashView)
        
        UIView .animate(withDuration: 0.1, animations: { () -> Void in
            
            flashView.alpha = 1
            
        }, completion: { b -> Void in
            
            UIView .animate(withDuration: 0.3, animations: { () -> Void in
                
                flashView.alpha = 0
                
            }, completion: { b in
                
                flashView .removeFromSuperview()
            })
            
        })
    }
    
    func snapImage() -> UIImage {
        
        UIGraphicsBeginImageContext(bounds.size)
        
        guard let currentContext = UIGraphicsGetCurrentContext() else { return UIImage() }
        
        layer .render(in: currentContext)
        
        let img = UIGraphicsGetImageFromCurrentImageContext()
        
        UIGraphicsEndImageContext()
        
        return img!
        
    }
    
    func smoothAddSubview(_ view: UIView, duration: TimeInterval, completion: ((Void)->Void)?) {
        
        let oldAlpha = view.alpha
        
        view.alpha = 0
        
        addSubview(view)
        
        UIView .animate(withDuration: duration, animations: {
            
            view.alpha = oldAlpha
            
        }, completion:  { b in completion?() })
        
    }
    
    func smoothHide(duration: TimeInterval, completion: ((Void)->Void)?) {
        
        UIView .animate(withDuration: duration, animations: { self.alpha = 0 }, completion: { b in completion?() })
    }
    
    func smoothChangeAlpha(_ a: CGFloat, duration: TimeInterval, completion: ((Void)->Void)?) {
        
        UIView .animate(withDuration: duration, animations: { self.alpha = a }, completion: { b in completion?() })
    }
    
}

extension UIVisualEffectView {
    
    
    func darken() {
        
        darken(0.33)
    }
    
    func lighten(){
        
        lighten(0.33)
    }
    
    func darken(_ duration: Double) {
        
        async_main {
            anim(duration){
                self.effect = UIBlurEffect(style: .dark)
            }
        }
    }
    
    func lighten(_ duration: Double){
        
        async_main {
            anim(duration){
                self.effect = UIBlurEffect(style: .light)
            }
        }
    }
    
}

class CircleView: UIView {
    
    var radius : CGFloat {
        set { edge = newValue*2 }
        get { return edge/2 }
    }
    convenience init(){
        self.init(frame: CGRect.zero)
        clipsToBounds = true
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = UIColor.clear
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateCornerRadius()
    }
    
    fileprivate func updateCornerRadius() {
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }
    
    override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        if event == "cornerRadius" {
            if let boundsAnimation = layer.animation(forKey: "bounds.size") as? CABasicAnimation {
                let animation = boundsAnimation.copy() as! CABasicAnimation
                animation.keyPath = "cornerRadius"
                let action = Action()
                action.pendingAnimation = animation
                action.priorCornerRadius = layer.cornerRadius
                return action
            }
        }
        return super.action(for: layer, forKey: event)
    }
    
    fileprivate class Action: NSObject, CAAction {
        var pendingAnimation: CABasicAnimation?
        var priorCornerRadius: CGFloat = 0
        @objc func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {
            if let layer = anObject as? CALayer, let pendingAnimation = pendingAnimation {
                if pendingAnimation.isAdditive {
                    pendingAnimation.fromValue = priorCornerRadius - layer.cornerRadius
                    pendingAnimation.toValue = 0
                } else {
                    pendingAnimation.fromValue = priorCornerRadius
                    pendingAnimation.toValue = layer.cornerRadius
                }
                layer.add(pendingAnimation, forKey: "cornerRadius")
            }
        }
    }
    
}

class CircleImageView: UIImageView {
    
    var radius : CGFloat {
        set { edge = newValue*2 }
        get { return edge/2 }
    }
    
    convenience init(){
        self.init(frame: CGRect.zero)
        clipsToBounds = true
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateCornerRadius()
    }
    
    fileprivate func updateCornerRadius() {
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }
    
    override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        if event == "cornerRadius" {
            if let boundsAnimation = layer.animation(forKey: "bounds.size") as? CABasicAnimation {
                let animation = boundsAnimation.copy() as! CABasicAnimation
                animation.keyPath = "cornerRadius"
                let action = Action()
                action.pendingAnimation = animation
                action.priorCornerRadius = layer.cornerRadius
                return action
            }
        }
        return super.action(for: layer, forKey: event)
    }
    
    fileprivate class Action: NSObject, CAAction {
        var pendingAnimation: CABasicAnimation?
        var priorCornerRadius: CGFloat = 0
        @objc func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {
            if let layer = anObject as? CALayer, let pendingAnimation = pendingAnimation {
                if pendingAnimation.isAdditive {
                    pendingAnimation.fromValue = priorCornerRadius - layer.cornerRadius
                    pendingAnimation.toValue = 0
                } else {
                    pendingAnimation.fromValue = priorCornerRadius
                    pendingAnimation.toValue = layer.cornerRadius
                }
                layer.add(pendingAnimation, forKey: "cornerRadius")
            }
        }
    }
    
}


class Ring:CircleView
{
    var color = UIColor.red
    var backColor = UIColor.clear
    var thickness = CGFloat(4)
    
    override func draw(_ rect: CGRect)
    {
        backColor.setFill()
        UIRectFill(rect)
        
        let ovalPath = UIBezierPath(ovalIn: bounds)
        color.setStroke()
        ovalPath.lineWidth = thickness
        ovalPath.stroke()
    }
    
}

class TransRing : Ring {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return false
    }
}


//  Adds closures to gesture setup. Just an example of using an extension.
//
//  Usage:
//
//  self.view.addGestureRecognizer(UITapGestureRecognizer(){
//      print("UITapGestureRecognizer")
//  })
//
//  let longpressGesture = UILongPressGestureRecognizer() {
//    print("UILongPressGestureRecognizer")
//  }
//  self.view.addGestureRecognizer(longpressGesture)
//
//  Michael L. Collard
//  collard@uakron.edu

import UIKit

// Global array of targets, as extensions cannot have non-computed properties
private var target = [Target]()

extension UIGestureRecognizer {
    
    convenience init(trailingClosure closure: @escaping (() -> ())) {
        // let UIGestureRecognizer do its thing
        self.init()
        
        target.append(Target(closure))
        self.addTarget(target.last!, action: #selector(Target.invoke))
    }
    
    func cancel(){
        isEnabled = false; isEnabled = true
    }
}

private class Target {
    
    // store closure
    fileprivate var trailingClosure: (() -> ())
    
    init(_ closure:@escaping (() -> ())) {
        trailingClosure = closure
    }
    
    // function that gesture calls, which then
    // calls closure
    /* Note: Note sure why @IBAction is needed here */
    @objc func invoke() {
        trailingClosure()
    }
}


extension UIScrollView {
    
    override func snapImage() -> UIImage {
        
        UIGraphicsBeginImageContext(contentSize)
        
        let savedContentOffset = contentOffset
        let savedFrame = frame
        
        contentOffset = CGPoint.zero
        frame = CGRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height)
        
        layer .render(in: UIGraphicsGetCurrentContext()!)
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        
        contentOffset = savedContentOffset;
        frame = savedFrame;
        
        UIGraphicsEndImageContext()
        
        return image!
    }
    
}

extension WKWebView {
    
    override func snapImage() -> UIImage {
        
        UIGraphicsBeginImageContextWithOptions(bounds.size, true, 0)
        drawHierarchy(in: bounds, afterScreenUpdates: false)
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return img!
    }
}

let colorsOrdered = [ UIColor.red, UIColor.orange, UIColor.yellow,UIColor.green, UIColor.magenta, UIColor.blue, UIColor.purple]

let colorDict = [
    "red" : UIColor.red,
    "orange" : UIColor.orange,
    "yellow" : UIColor.yellow,
    "green" : UIColor.green,
    "magenta" : UIColor.magenta,
    "blue" : UIColor.blue,
    "purple" : UIColor.purple
]

extension UIColor {
    
    static func colorWithName(_ colorName:String)->UIColor{
        
        guard let colorPair = colorDict .filter ({ $0.0 == colorName }).first else { return UIColor.gray }
        
        return colorPair.1
    }
    
    static func randomColor() -> UIColor{
        
        let rand = arc4random_uniform(UInt32(colorsOrdered.count))
        let color = colorsOrdered[Int(rand)]
        
        return color
    }
    
    var name: String {
        
        guard let colorPair = colorDict .filter ({ $0.1 == self }).first else { return "gray" }
        
        return colorPair.0
    }
    
    func gray(factor:CGFloat)-> UIColor {
        
        return self.color(UIColor.gray, factor: factor)
    }
    
    func lightGray(factor:CGFloat)-> UIColor {
        
        return self.color(UIColor.lightGray, factor: factor)
        
    }
    
    func darken()->UIColor{
        return self.color(UIColor.darkGray, factor: 1.2).color(UIColor.black, factor: 1.2)
    }
    
    func color(_ color: UIColor, factor: CGFloat) -> UIColor {
        
        let color1 = color//UIColor.lightGrayColor()
        let color2 = self
        
        var (r1, g1, b1, a1):(CGFloat,CGFloat,CGFloat,CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2):(CGFloat,CGFloat,CGFloat,CGFloat) = (0, 0, 0, 0)
        
        color1.getRed(&r1, green:&g1, blue:&b1, alpha:&a1)
        color2.getRed(&r2, green:&g2, blue:&b2, alpha:&a2)
        
        let mix = UIColor(red:(factor*r1+r2)/(factor+1),
                          green:(factor*g1+g2)/(factor+1),
                          blue:(factor*b1+b2)/(factor+1),
                          alpha:(factor*a1+a2)/(factor+1))
        
        return mix
        
    }
    
    
}

//Images
/*
 func cropImageToRect(image :UIImage, rect: CGRect) -> UIImage {
 
 let imageRef = CGImageCreateWithImageInRect(image.CGImage, rect);
 guard let cropped = CGImageCreateWithImageInRect(imageRef, rect) else { return image }
 return orientImageWithDevice(cropped)
 }*/

func resizeImage(_ ciImage: CIImage, scale: CGFloat, orient: Bool=false) -> UIImage {
    
    let image = orient ? orientImageWithDevice(ciImage) : UIImage(ciImage: ciImage)
    
    return resizeImage(image, scale: scale)
    
}

func resizeImage(_ image: UIImage, scale: CGFloat)->UIImage{
    
    let newHeight = image.size.height * scale
    let newWidth = image.size.width * scale
    
    return resizeImage(image, newWidth: newWidth, newHeight: newHeight)
}

func resizeImage(_ image: UIImage, newWidth: CGFloat, newHeight: CGFloat)->UIImage{
    
    UIGraphicsBeginImageContext(CGSize(width: floor(newWidth), height: floor(newHeight)))
    image .draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return newImage!
}

func resizeImage(_ image: CIImage, newWidth: CGFloat, newHeight: CGFloat)->UIImage{
    
    return resizeImage(UIImage(ciImage: image), newWidth: newWidth, newHeight: newHeight)
}

func cropImage(_ image: CIImage, to rect: CGRect, margin: CGFloat=0)-> CIImage{
    
    var rect = rect.insetBy(dx: -margin, dy: -margin)//add margin
    rect = rect.applying(CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -image.extent.height))//convert to CoreImage coordinates
    
    let cropped = image.cropping(to: rect)
    return cropped.applying(CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y))
}

func checkLandscape()->Bool {
    
    switch UIDevice.current.orientation {
        
    case .landscapeLeft, .landscapeRight: return true
        
    case .portrait, .portraitUpsideDown: return false
        
    default:
        return true
    }
}

func rotatePortraitImage(_ image: CIImage) -> CIImage? {
    
    let statusBarOrientation = UIApplication.shared.statusBarOrientation
    
    switch UIDevice.current.orientation {
        
    case .landscapeLeft: return nil
        
    case .landscapeRight: return nil
        
    case .portrait:
        
        if statusBarOrientation == .landscapeRight {
            //rotate right
            return image.applying(CGAffineTransform(rotationAngle: DegToRad(-90))).applying(CGAffineTransform(translationX: 0, y: image.extent.size.width))
            
        } else {
            //rotate left
            return image.applying(CGAffineTransform(rotationAngle: DegToRad(90))).applying(CGAffineTransform(translationX: image.extent.size.height, y: 0))
            
        }
        
    case .portraitUpsideDown:
        
        if statusBarOrientation == .landscapeRight {
            //rotate left
            return image.applying(CGAffineTransform(rotationAngle: DegToRad(90))).applying(CGAffineTransform(translationX: image.extent.size.height, y: 0))
            
        } else {
            //rotate right
            return image.applying(CGAffineTransform(rotationAngle: DegToRad(-90))).applying(CGAffineTransform(translationX: 0, y: image.extent.size.width))
            
        }
        
    default:
        return nil
    }
    
}

func orientImageWithDevice(_ image: CIImage) -> UIImage {
    
    switch UIDevice.current.orientation {
        
    case .landscapeLeft: return UIImage(ciImage: image, scale: 1, orientation: .up)
        
    case .landscapeRight: return UIImage(ciImage: image, scale: 1, orientation: .down)
        
    case .portrait: return UIImage(ciImage: image, scale: 1, orientation: .right)
        
    case .portraitUpsideDown: return UIImage(ciImage: image, scale: 1, orientation: .left)
        
    default:
        return UIImage(ciImage: image, scale: 1, orientation: .up)
    }
    
}

func createCGImage(_ inputImage: CIImage) -> CGImage! {
    let context = CIContext(options: nil)
    return context.createCGImage(inputImage, from: inputImage.extent)
}

extension UIViewController {
    
    func executeBackgroundTask(_ task: @escaping (_ end: @escaping(Void)->Void)->Void){
        
        async_main{
            //background task to continue even if App is closed
            var backTask = UIBackgroundTaskIdentifier()
            backTask = UIApplication.shared.beginBackgroundTask(withName: "background task") {
                
                //clean up if necessary
                
                UIApplication.shared.endBackgroundTask(backTask)
                backTask = UIBackgroundTaskInvalid
            }
            
            task(){
                UIApplication.shared.endBackgroundTask(backTask)
                backTask = UIBackgroundTaskInvalid
            }
        }
    }
    
    func executeBackgroundTask_serial(_ queue: DispatchQueue, task: @escaping (_ end: @escaping(Void)->Void)->Void){
        
        async {
            //background task to continue even if App is closed
            var backTask = UIBackgroundTaskIdentifier()
            
            backTask = UIApplication.shared.beginBackgroundTask(withName: "background task") {
                
                //clean up if necessary
                
                UIApplication.shared.endBackgroundTask(backTask)
                backTask = UIBackgroundTaskInvalid
            }
            
            sync_wait { (go) in
                async_serial_main_wait(queue){ next in
                    task(){
                        next()
                        UIApplication.shared.endBackgroundTask(backTask)
                        backTask = UIBackgroundTaskInvalid
                        go()
                    }
                    
                }
            }
        }
        
        
    }
    
    
}

func async(_ block: (()->())?){
    
    guard let block = block else { return }
    
    DispatchQueue.global().async(execute: block)
    
}


func sync(_ block: (()->())?){
    
    guard let block = block else { return }
    
    DispatchQueue.global().sync(execute: block)
    
}

func async_main(_ block:(()->())?){
    guard let block = block else { return }
    
    DispatchQueue.main.async(execute: block)
}

func sync_main(_ block:(()->())?){
    guard let block = block else { return }
    
    if Thread.isMainThread {// if already in main just execute code
        block()
    } else {
        DispatchQueue.main.sync(execute: block)
    }
    
}

func serial_handle(_ name: String)->DispatchQueue{
    return DispatchQueue(label: name, attributes: [])
}

func serial_handle()->DispatchQueue{
    return serial_handle("serialQueue")
}

func async_serial(_ queue: DispatchQueue?, block:((Void)->Void)?){
    
    guard let block = block else { return }
    guard let queue = queue else { return }
    
    queue.async(execute: block)
    
}

func async_serial_wait(_ queue: DispatchQueue, block: ((_ next:@escaping(Void)->Void)->Void)?){
    
    guard let block = block else { return }
    
    queue.async {
        queue.suspend()
        block { queue.resume() }
    }
    
}

func async_serial_main(_ queue: DispatchQueue, block:((Void)->Void)?){
    
    guard let block = block else { return }
    
    async_serial_wait(queue) { next in async_main { block(); next() } }
    
}

func async_serial_main_wait(_ queue: DispatchQueue, block:((_ next:@escaping(Void)->Void)->Void)?){
    
    guard let block = block else { return }
    
    async_serial(queue) {
        queue.suspend()
        async_main{ block { queue.resume() } }
    }
}

func group_handle()->DispatchGroup{
    return DispatchGroup()
}

func async_group(_ group: DispatchGroup ,block: (()->())?){
    guard let block = block else { return }
    DispatchQueue.global().async(group: group, execute: block)
}

func async_group_main(_ group: DispatchGroup, block:(()->())?){
    guard let block = block else { return }
    DispatchQueue.main.async(group: group, execute: block)
}

func async_group_wait(_ group: DispatchGroup, block:((_ go:@escaping(Void)->Void)->Void)?){
    
    guard let block = block else { return }
    
    async_group(group) {
        sync_wait({ (go) in block(){ go() } })
    }
}

func async_group_main_wait(_ group:DispatchGroup, block:((_ go:@escaping(Void)->Void)->Void)?){
    guard let block = block else { return }
    
    async_group(group) {
        sync_wait{ go in sync_main { block(){ go() } } }
    }
}

func async_after(_ group: DispatchGroup, block: (()->())?){
    
    guard let block = block else { return }
    
    group.notify(queue: DispatchQueue.global(), execute: block)
}

func async_main_after(_ group: DispatchGroup, block: (()->())?){
    
    guard let block = block else { return }
    
    group.notify(queue: DispatchQueue.main, execute: block)
}


func sync_wait(_ block: ((_ go:@escaping(Void)->Void)->Void)?){
    
    guard let block = block else { return }
    
    let s = serial_handle()
    
    s.suspend()
    block { s.resume() }
    s.sync{}
}

typealias Singleton = (op: OperationQueue,ser: DispatchQueue)

func singleton_handle()-> Singleton{
    return (OperationQueue(),serial_handle())
}

func async_singleton(_ s: Singleton?, block: ((Void)->Void)?){
    
    guard let block = block else { return }
    
    async_serial(s?.ser) {//to make sure checking op count always happens in a single thread
        let operation = BlockOperation(block: block)
        operation.queuePriority = .normal
        operation.qualityOfService = .default
        
        if s?.op.operationCount == 0 {
            s?.op.addOperation(operation)
        }
    }
    
    //skip otherwise
}

func async_singleton(_ s: Singleton?, killAfter d: Double, block:((_ cancelled:@escaping(Void)->Bool)->Void)?){
    
    guard let block = block else { return }
    
    async_serial(s?.ser) {//to make sure checking op count always happens in a single thread
        let operation = BlockOperation()
        operation.addExecutionBlock { [unowned operation] in
            block { operation.isCancelled }
        }
        operation.queuePriority = .normal
        operation.qualityOfService = .default
        
        if s?.op.operationCount == 0 {
            s?.op.addOperation(operation)
            
            delay_main(d){
                guard let ops = s?.op.operations else { return }
                
                if ops.contains(operation) {
                    s?.op.cancelAllOperations()
                    
                    print("singleton cancelled!")
                }
                
            }
        } else {
            //print("singleton busy!")
        }
    }
    
}

func async_singleton_wait(_ s: Singleton?, block: ((_ end:@escaping(Void)->Void)->Void)?){
    
    guard let block = block else { return }
    
    async_serial(s?.ser) {//to make sure checking op count always happens in a single thread
        let operation = BlockOperation(){
            sync_wait{ go in block { go() } }
        }
        operation.queuePriority = .normal
        operation.qualityOfService = .default
        
        if s?.op.operationCount == 0 {
            s?.op.addOperation(operation)
        }
        //skip otherwise
        
    }
    
}

func oneShot(_ block: inout ((Void)->Void)?){
    
    block?()
    block = nil
}

func delay_main(_ after:Double, block:(()->())?){
    
    guard let block = block else { return }
    
    let delay = DispatchTime.now() + Double(Int64(after * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
    
    DispatchQueue.main.asyncAfter(deadline: delay, execute: block)
    
}

func delay_serial(_ queue: DispatchQueue, after:Double,block:(()->())?){
    
    guard let block = block else { return }
    
    let delay = DispatchTime.now() + Double(Int64(after * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
    
    queue.asyncAfter(deadline: delay, execute: block)
}


func delay_serial_wait(_ queue: DispatchQueue, after:Double,block:((_ next:@escaping(Void)->Void)->Void)?){
    
    guard let block = block else { return }
    
    let delay = DispatchTime.now() + Double(Int64(after * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
    
    queue.asyncAfter(deadline: delay){
        queue.suspend()
        block { queue.resume() }
    }
}


func delay(_ queue:DispatchQueue, after:Double,block:(()->())?){
    let delay = DispatchTime.now() + Double(Int64(after * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
    if let block = block {
        queue.asyncAfter(deadline: delay, execute: block)
    }
}

func halt(_ duration: Double){
    
    sync_wait { go in
        delay_main(duration, block: go)
    }
}

func skip(_ block:(()->())?){}


extension DispatchQueue{
    
    func async_repeat(_ times: Int, every: Double, block:((Void)->Void)?)->Timer?{
        
        guard let block = block else { return nil }
        
        let noCount = times<2
        var count = 0
        
        let timer = Timer.scheduledTimer(withTimeInterval: every, repeats: times != 1){ (timer) in
            self.async(execute: block)
            
            if !noCount {
                count += 1
                if count>=times { timer.invalidate() }
            }
            
        }
        return timer
    }
}

private var tapLock = false
private let lockQueue = DispatchQueue(label: "lock queue", attributes: [])
func lock(_ duration:Double)->Bool{
    var proceed = true
    lockQueue.sync{
        if tapLock == false {
            tapLock = true
            delay(lockQueue,after: duration){
                tapLock = false
            }
        } else {
            proceed = false
        }
    }
    return proceed
}

func docFlagExists(_ name: String)-> Bool{
    
    let fileManager = FileManager.default
    let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    
    let path = docsDir + "/"+name
    return fileManager.fileExists(atPath: path)
}

func setDocFlag(_ name: String){
    let fileManager = FileManager.default
    let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    
    let path = docsDir + "/"+name
    fileManager.createFile(atPath: path, contents: nil, attributes: nil)
}

func deleteDocFlag(_ name: String){
    let fileManager = FileManager.default
    let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    
    let path = docsDir + "/"+name
    do {
        try fileManager.removeItem(at: URL(fileURLWithPath: path))
    } catch let error as NSError {
        print(error.localizedDescription)
    }
}

func deleteFileDoc(_ name: String) -> Bool{
    
    let fileManager = FileManager.default
    let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    let path = docsDir + "/" + name
    
    guard fileManager.fileExists(atPath: path) else { return false }
    
    do {
        try fileManager.removeItem(atPath: path)
    } catch let error as NSError {
        NSLog("could not remove \(path)")
        print(error.localizedDescription)
    }
    
    return true
}

func renameFileDoc(old OldName: String, new name: String){
    
    let fileManager = FileManager.default
    let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    
    let path = docsDir + "/" + OldName
    let newPath = docsDir + "/" + name
    
    do {
        try fileManager.moveItem(atPath: path, toPath: newPath)
    }
    catch let error as NSError {
        print("Can't move file: \(error)")
    }
    
}

func moveFileDoc(_ path: String, newName name: String){
    
    let fileManager = FileManager.default
    let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    
    let newPath = docsDir + "/" + name
    
    do {
        try fileManager.moveItem(atPath: path, toPath: newPath)
    }
    catch let error as NSError {
        print("Can't move file: \(error)")
    }
}

func loadImageDoc(_ name : String)->UIImage?{
    
    var image : UIImage? = nil
    
    let fileManager = FileManager.default
    let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    
    let path = docsDir + "/" + name
    
    if let prevData = fileManager.contents(atPath: path) {
        image = UIImage(data: prevData)
    }
    
    return image
}

func saveImageDoc(_ image: UIImage, name: String){
    
    let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    let path = docsDir + "/" + name
    
    if let JPEG = UIImageJPEGRepresentation(image,0.7){
        try? JPEG.write(to: URL(fileURLWithPath: path), options: [.atomic])
    }
    
}

func loadImage(_ path : String)->UIImage?{
    
    var image : UIImage? = nil
    
    let fileManager = FileManager.default
    
    if let prevData = fileManager.contents(atPath: path) {
        image = UIImage(data: prevData)
    }
    
    return image
}

func deleteFile(_ path:String){
    
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: path) else { return }
    
    do {
        try fileManager.removeItem(atPath: path)
    } catch let error as NSError {
        NSLog("could not remove \(path)")
        print(error.localizedDescription)
    }
    return
}

func anim(_ duration: Double, actions: @escaping (Void)->Void, completion: ((Void)->Void)?){
    UIView .animate(withDuration: duration, animations: actions, completion: { _ in completion?()})
}

func anim(_ duration:Double,actions: @escaping (Void)->Void){
    anim(duration,actions: actions, completion: nil)
}


/*
 //make Int conform to SequenceType
 extension Int : SequenceType {
 public func generate() -> RangeGenerator<Int> {
 return (0..<self).generate()
 }
 }
 */
