//
//  SearchBoxDelegate.swift
//  SearchBox
//
//  Created by Doug Stein on 4/24/18.
//  Copyright © 2018 Doug Stein. All rights reserved.
//

import Alamofire
import PromiseKit

protocol SearchBoxDelegate {
    func completions(for text: String) -> (Request?, Promise<[(String,String)]>)
    
    func search(for text: String)
}
