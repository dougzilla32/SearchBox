//
//  SearchBoxDelegate.swift
//  SearchBox
//
//  Created by Doug Stein on 4/24/18.
//

import PromiseKit

public protocol SearchBoxDelegate {
    func completions(for text: String) -> CancellablePromise<[(String,String)]>
}
