//
//  SearchBoxDelegate.swift
//  SearchBox
//
//  Created by Doug Stein on 4/24/18.
//

import Alamofire
import CancelForPromiseKit

public protocol SearchBoxDelegate {
    func completions(for text: String) -> CancellablePromise<[(String,String)]>
}
