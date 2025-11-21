//  Created by Stas Kirichok on 28-08-2018.
//  Copyright 2025 EPAM Systems
//  
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  
//      https://www.apache.org/licenses/LICENSE-2.0
//  
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import UIKit

class SummatorViewController: UIViewController {
  
  @IBOutlet private var firstField: UITextField!
  @IBOutlet private var secondField: UITextField!
  @IBOutlet private var resultField: UITextField!
  
  private let summator = SummatorService()
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    
    firstField.delegate = self
    secondField.delegate = self
  }
  
  private func calculateSum() {
    let firstNumber = Int(firstField.text!) ?? 0
    let secondNumber = Int(secondField.text!) ?? 0
    let result = summator.addNumbers(first: firstNumber, second: secondNumber)
    resultField.text = "\(result)"
  }
  
}

extension SummatorViewController: UITextFieldDelegate {
  
  func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
    textField.text = (textField.text! as NSString).replacingCharacters(in: range, with: string)
    calculateSum()
    
    return false
  }
  
}
