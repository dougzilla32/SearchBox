//
//  SearchBoxDelegate.swift
//  SearchBox
//
//  Created by Doug Stein on 4/24/18.
//  Copyright © 2018 Doug Stein. All rights reserved.
//

import Alamofire
import PromiseKit

public protocol SearchBoxDelegate {
    func completions(for text: String) -> Promise<[(String,String)]>
}
