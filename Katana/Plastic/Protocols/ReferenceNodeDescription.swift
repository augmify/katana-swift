//
//  ReferenceNodeDescription.swift
//  Katana
//
//  Created by Mauro Bolis on 19/08/16.
//  Copyright © 2016 Bending Spoons. All rights reserved.
//

import Foundation

// type erasure for PlasticNodeDescription
public protocol AnyPlasticNodeDescription {
  static func _layout(views: ViewsContainer, props: Any, state: Any) -> Void
}

// a node that has a reference size
public protocol ReferenceNodeDescription {
  static func referenceSize() -> CGSize
}

// a node that leverages plastic to layout
public protocol PlasticNodeDescription: AnyPlasticNodeDescription {
  associatedtype Props
  associatedtype State
  static func layout(views: ViewsContainer, props: Props, state: State) -> Void
}

public extension PlasticNodeDescription {
  static func _layout(views: ViewsContainer, props: Any, state: Any) -> Void {
    if let p = props as? Props, let s = state as? State {
      layout(views: views, props: p, state: s)
    }
  }
}