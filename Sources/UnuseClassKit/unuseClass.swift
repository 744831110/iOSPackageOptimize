//
//  File.swift
//  
//
//  Created by 陈谦 on 2020/8/22.
//

import Foundation
import PathKit

public func findUnrefsClass(path: String) {
    guard let filePath = verifiedAppPath(path: path) else {
        print("Error: \(#function) invalid app path")
        exit(EX_USAGE)
    }
    let unrefSymbols = findClassUnrefSymbols(path: filePath.string, reservedPrefix: "", filterPrefix: "")
    print(unrefSymbols)
    let fileManager = FileManager.default
    var resultString = ""
    for symbol in unrefSymbols {
        let string = symbol + "\n"
        resultString.append(string)
    }
    let success = fileManager.createFile(atPath: fileManager.currentDirectoryPath + "result.txt", contents: Data(base64Encoded: resultString, options: .ignoreUnknownCharacters))
    print("save result in file \(success ? "success" : "fail")")
}



public func verifiedAppPath(path: String) -> Path? {
    var filePath = Path(path)
    if filePath.extension == "app" {
        let appName = filePath.lastComponentWithoutExtension
        filePath = filePath + Path(appName)
        if appName.hasSuffix("-iPad") {
            filePath = Path(filePath.string.replacingOccurrences(of: "-iPad", with: ""))
        }
    }
    guard filePath.exists else {
        print("Error: \(#function) app path is not exist \(filePath.string)")
        return nil
    }
    
    let command = CommandProcess(execute: "file -b \(filePath.string)")
    guard let cmd = command, let result = cmd.execute() else {
        return nil
    }
    
    guard result.prefix(6) == "Mach-O" else {
        print("Error: \(#function) file type prefix is error \(result)")
        return nil
    }
    return filePath
}

func findClassUnrefSymbols(path: String, reservedPrefix: String, filterPrefix: String) -> Set<String> {
    var unrefSymbols = Set<String>()
    let command = CommandProcess(execute: "file -b \(path)")
    guard let result = command?.execute(), let binaryFileArch = result.split(separator: " ").last else {
        print("Error: \(#function) get binaryFileArch fail")
        return unrefSymbols
    }
    let binaryFileArchString = String(binaryFileArch)
    let unrefPointers = findClassPointers(path: path, binaryFileArch: binaryFileArchString, pointerType: "__objc_classlist").subtracting(findClassPointers(path: path, binaryFileArch: binaryFileArchString, pointerType: "__objc_classrefs"))
    guard unrefPointers.count != 0 else {
        print("Finish: class unref pointer null")
        exit(EX_USAGE)
    }
    let symbols = getClassSymbols(path: path)
    for unrefPointer in unrefPointers {
        guard symbols.contains(where: { (key: String, value: String) -> Bool in
            return key == unrefPointer
        }), let unrefSymbol = symbols[unrefPointer] else {
            continue
        }
        if reservedPrefix.count > 0 && unrefSymbol.starts(with: reservedPrefix) {
            continue
        }
        if filterPrefix.count > 0 && unrefSymbol.starts(with: filterPrefix) {
            continue
        }
        unrefSymbols.insert(unrefSymbol)
    }
    if unrefSymbols.count == 0 {
        print("Finish: class unref symbols null")
        exit(EX_USAGE)
    }
    return unrefSymbols
}

func findClassPointers(path: String, binaryFileArch: String, pointerType:String) -> Set<String> {
    var list = Set<String>()
    guard let command = CommandProcess(execute: "/usr/bin/otool -v -s __DATA \(pointerType) \(path)") else {
        return list
    }
    guard let result = command.executeToArray(), result.count != 0 else {
        return list
    }
    for line in result {
        guard let pointers = pointersFromBinary(line: line, binaryFileArch: binaryFileArch) else {
            continue
        }
        list = list.union(pointers)
    }
    if list.count == 0 {
        print("Error: \(#function) get \(pointerType) pointers null")
        exit(EX_USAGE)
    }
    return list
}

func pointersFromBinary(line: String, binaryFileArch: String) -> Set<String>? {
    if line.count < 16 {
        return nil
    }
    var binaryLine = line
    var pointers = Set<String>()
    let startIndex = binaryLine.startIndex
    let endIndex = binaryLine.index(startIndex, offsetBy: 16)
    let range = startIndex...endIndex
    binaryLine.removeSubrange(range)
    let array = Array(binaryLine.components(separatedBy: " "))
    if binaryFileArch == "x86_64" {
        if array.count >= 8 {
            pointers.insert(array[4...8].reversed().joined() + array[0...4].reversed().joined())
        }
        if array.count >= 16 {
            pointers.insert(array[12...16].reversed().joined() + array[8...12].reversed().joined())
        }
    }
    if binaryFileArch.starts(with: "arm") {
        if array.count >= 2 {
            pointers.insert(array[1]+array[0])
        }
        if array.count >= 4 {
            pointers.insert(array[3]+array[2])
        }
    }
    return pointers
}

func getClassSymbols(path: String) -> [String : String] {
    var symbols = [String : String]()
    guard let regex = try? NSRegularExpression(pattern: "(\\w{16}) .* _OBJC_CLASS_\\$_(.+)") else {
        print("Error: \(#function) create regex fail")
        return symbols
    }
    guard let command = CommandProcess(execute: "nm -nm \(path)"), let result = command.executeToArray(), result.count != 0 else {
        return symbols
    }
    for line in result {
        guard let regexResult = regex.firstMatch(in: line, range: NSMakeRange(0, line.count)), regexResult.numberOfRanges < 3 else {
            continue
        }
        let addressStartIndex = line.index(line.startIndex, offsetBy: regexResult.range(at: 1).location)
        let addressEndIndex = line.index(addressStartIndex, offsetBy: regexResult.range(at: 1).length)
        let address = String(line[addressStartIndex ... addressEndIndex])
        let symbolStartIndex = line.index(line.startIndex, offsetBy: regexResult.range(at: 2).location)
        let symbolEndIndex = line.index(symbolStartIndex, offsetBy: regexResult.range(at: 2).length)
        let symbol = String(line[symbolStartIndex ... symbolEndIndex])
        symbols[address] = symbol
        guard symbols.count != 0 else {
            print("Error: \(#function) class symbols null")
            exit(EX_USAGE)
        }
        return symbols
    }
    return symbols
}

func filterSuperClass(path:String, unrefSymbols: Set<String>) -> Set<String> {
    var symbols = unrefSymbols
    guard let subclassRegex = try? NSRegularExpression(pattern: "\\w{16} 0x\\w{9} _OBJC_CLASS_\\$_(.+)") else {
        print("Error: \(#function) create subclass regex fail, filter super class fail")
        return symbols
    }
    guard let superclassRegex = try? NSRegularExpression(pattern: "\\s*superclass 0x\\w{9} _OBJC_CLASS_\\$_(.+)") else {
        print("Error: \(#function) create superclass regex fail, filter super class fail");
        return symbols
    }
    guard let command = CommandProcess(execute: "/usr/bin/otool -oV \(path)"), let result = command.executeToArray(), result.count != 0 else {
        print("Error: \(#function) command /usr/bin/otool -oV \(path) fail, filter super class fail");
        return symbols
    }
    var subclassName = ""
    var superclassName = ""
    for line in result {
        if let subclassRegexResult = subclassRegex.firstMatch(in: line, range: NSMakeRange(0, line.count)) {
            let startIndex = line.index(line.startIndex, offsetBy: subclassRegexResult.range(at: 0).location)
            let endIndex = line.index(startIndex, offsetBy: subclassRegexResult.range(at: 0).length)
            subclassName = String(line[startIndex ... endIndex])
        }
        if let superclassRegexResult = superclassRegex.firstMatch(in: line, range: NSMakeRange(0, line.count)) {
            let startIndex = line.index(line.startIndex, offsetBy: superclassRegexResult.range(at: 0).location)
            let endIndex = line.index(startIndex, offsetBy: superclassRegexResult.range(at: 0).length)
            superclassName = String(line[startIndex ... endIndex])
        }
        guard subclassName.count > 0, superclassName.count > 0 else {
            continue;
        }
        if symbols.contains(superclassName) && !symbols.contains(subclassName) {
            symbols.remove(superclassName)
            subclassName = ""
            superclassName = ""
        }
    }
    return symbols;
}
