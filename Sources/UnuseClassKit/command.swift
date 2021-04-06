//
//  File.swift
//  
//
//  Created by 陈谦 on 2020/8/22.
//

import Foundation

public class CommandProcess {
    let p: Process
    
    public init(executePath: String, arguments: [String]) {
        p = Process()
        if #available(OSX 10.13, *) {
            p.executableURL = URL(fileURLWithPath: executePath)
        } else {
            p.launchPath = executePath
        }
        p.arguments = arguments
    }
    
    public init?(path: String = "/usr/bin/", execute: String) {
        p = Process()
        let command = path+execute;
        let array = command.components(separatedBy: " ")
        if array.isEmpty {
            print("command init fail")
            return nil
        }
        if #available(OSX 10.13, *) {
            p.executableURL = URL(fileURLWithPath: array[0])
        } else {
            p.launchPath = array[0]
        }
        p.arguments = Array(array.dropFirst())
    }
    
    public func execute() -> String? {
        let pipe = Pipe()
        p.standardOutput = pipe;
        
        let fileHandle = pipe.fileHandleForReading;
        if #available(OSX 10.13, *) {
            do {
                try p.run()
            } catch {
                print("execute is fail \(error)")
                return nil
            }
        } else {
            p.launch()
        }
        let data = fileHandle.readDataToEndOfFile()
        guard var string = String(data: data, encoding: .utf8) else {
            return nil
        }
        if(string[string.index(before: string.endIndex)] == "\n") {
            string.removeLast();
        }
        return string;
    }
    
    public func executeToArray() -> Array<String>? {
        guard let result = execute() else {
            return nil;
        }
        return Array(result.components(separatedBy: "\n"));
    }
}
