//
//  Node.swift
//  Katana
//
//  Created by Luca Querella on 09/08/16.
//  Copyright © 2016 Bending Spoons. All rights reserved.
//

import UIKit

private typealias ChildrenDictionary = [Int:[(node: AnyNode, index: Int)]]

public protocol AnyNode: class {
  var anyDescription : AnyNodeDescription { get }
  var children : [AnyNode]? { get }
  var store: AnyStore { get }
  var parentNode: AnyNode? {get}

  func draw(container: DrawableContainer)
  func update(description: AnyNodeDescription) throws
  func update(description: AnyNodeDescription, parentAnimation: Animation) throws
}

public class Node<Description: NodeDescription>: ConnectedNode, AnyNode {
  
  public private(set) var children : [AnyNode]?
  public private(set) unowned var store: AnyStore
  private(set) var state : Description.StateType
  private(set) var description : Description
  public private(set) weak var parentNode: AnyNode?
  private var container: DrawableContainer?  
  
  public var anyDescription: AnyNodeDescription {
    get {
      return self.description
    }
  }
  
  public init(description: Description, parentNode: AnyNode?, store: AnyStore) {
    self.description = description
    self.state = Description.StateType.init()
    self.parentNode = parentNode
    self.store = store
    
    let update = { [weak self] (state: Description.StateType) -> Void in
      self?.update(state: state)
    }
    
    self.description.props = self.updatedPropsWithConnect(description: description, props: self.description.props)

    let children  = Description.render(props: self.description.props,
                                       state: self.state,
                                       update: update,
                                       dispatch: self.store.dispatch)
    
    self.children =  self.processChildrenBeforeDraw(children).map {
      $0.node(parentNode: self)
    }
  }
  
  
  // Customization point for sublcasses. It allowes to update the children before they get drawn
  func processChildrenBeforeDraw(_ children: [AnyNodeDescription]) -> [AnyNodeDescription] {
    return children
  }

  func update(state: Description.StateType)  {
    self.update(state: state, description: self.description, parentAnimation: .none)
  }
  
  public func update(description: AnyNodeDescription) throws {
    try self.update(description: description, parentAnimation: .none)
  }
  
  public func update(description: AnyNodeDescription, parentAnimation animation: Animation = .none) throws {
    var description = description as! Description
    description.props = self.updatedPropsWithConnect(description: description, props: description.props)
    self.update(state: self.state, description: description, parentAnimation: animation)
  }
  
  private func update(state: Description.StateType, description: Description, parentAnimation: Animation) {
    guard let children = self.children else {
      fatalError("update should not be called at this time")
    }
    
    guard self.description.props != description.props || self.state != state else {
      return
    }
    
    let childrenAnimation = type(of: self.description).childrenAnimationForNextRender(
      currentProps: self.description.props,
      nextProps: description.props,
      currentState: self.state,
      nextState: state,
      parentAnimation: parentAnimation
    )
    
    self.description = description
    self.state = state
    
    var currentChildren = ChildrenDictionary()
    
    for (index,child) in children.enumerated() {
      let key = child.anyDescription.replaceKey
      let value = (node: child, index: index)
      
      if currentChildren[key] == nil {
        currentChildren[key] = [value]
      } else {
        currentChildren[key]!.append(value)
      }
    }
    
    let update = { [weak self] (state: Description.StateType) -> Void in
      self?.update(state: state)
    }
    
    var newChildren = Description.render(props: self.description.props,
                                         state: self.state,
                                         update: update,
                                         dispatch: self.store.dispatch)
    
    newChildren = self.processChildrenBeforeDraw(newChildren)
    
    var nodes : [AnyNode] = []
    var viewIndexes : [Int] = []
    var childrenToAdd : [AnyNode] = []
    
    for newChild in newChildren {
      let key = newChild.replaceKey
      
      let childrenCount = currentChildren[key]?.count ?? 0
      
      if childrenCount > 0 {
        let replacement = currentChildren[key]!.removeFirst()
        assert(replacement.node.anyDescription.replaceKey == newChild.replaceKey)
        
        try! replacement.node.update(description: newChild, parentAnimation: childrenAnimation)
        
        nodes.append(replacement.node)
        viewIndexes.append(replacement.index)
        
      } else {
        //else create a new node
        let node = newChild.node(parentNode: self)
        viewIndexes.append(children.count + childrenToAdd.count)
        nodes.append(node)
        childrenToAdd.append(node)
      }
    }
    
    self.children = nodes
    self.redraw(childrenToAdd: childrenToAdd, viewIndexes: viewIndexes, animation: parentAnimation)
  }

  
  func updatedPropsWithConnect(description: Description, props: Description.PropsType) -> Description.PropsType {
    if let desc = description as? AnyConnectedNodeDescription {
      // description is connected to the store, we need to update it
      let state = self.store.getAnyState()
      return type(of: desc).anyConnect(parentProps: description.props, storageState: state) as! Description.PropsType
    }
    
    return props
  }

  
  public func draw(container: DrawableContainer) {
    guard let children = self.children else {
      fatalError("draw cannot be called at this time")
    }
    
    if (self.container != nil)  {
      fatalError("draw can only be call once on a node")
    }
    
    self.container = container.add { Description.NativeView() }
    
    let update = { [weak self] (state: Description.StateType) -> Void in
      self?.update(state: state)
    }
    
    self.container?.update { view in
      Description.applyPropsToNativeView(props: self.description.props,
                                         state: self.state,
                                         view: view as! Description.NativeView,
                                         update: update,
                                         node: self)
    }
    
    children.forEach { $0.draw(container: self.container!) }
  }
  
  private func redraw(childrenToAdd: [AnyNode], viewIndexes: [Int], animation: Animation) {
    guard let container = self.container else {
      return
    }
    
    assert(viewIndexes.count == self.children?.count)
    
    let update = { [weak self] (state: Description.StateType) -> Void in
      self?.update(state: state)
    }
    
    animation.animateBlock {
      container.update { view in
        Description.applyPropsToNativeView(props: self.description.props,
                                           state: self.state,
                                           view: view as! Description.NativeView,
                                           update: update,
                                           node: self)
      }
    }
    
    childrenToAdd.forEach { node in
      return node.draw(container: container)
    }
    
    var currentSubviews : [DrawableContainerChild?] =  container.children().map { $0 }
    let sorted = viewIndexes.isSorted
    
    for viewIndex in viewIndexes {
      let currentSubview = currentSubviews[viewIndex]!
      if (!sorted) {
        container.bringToFront(child: currentSubview)
      }
      currentSubviews[viewIndex] = nil
    }
    
    for view in currentSubviews {
      if let viewToRemove = view {
        self.container?.remove(child: viewToRemove)
      }
    }
  }

}