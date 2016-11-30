//
//  ViewController.swift
//  AudioRecordDemo
//
//  Created by WeiHu on 2016/11/25.
//  Copyright © 2016年 WeiHu. All rights reserved.
//

import UIKit
import AudioToolbox
import AVFoundation

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        if let path = Bundle.main.path(forResource: "MP3Sample", ofType: "mp3"),let file = FileHandle(forReadingAtPath: path){
            
            do {
//                var fileSize: Int = 4620392
                let value: [FileAttributeKey : Any] = try FileManager.default.attributesOfItem(atPath: path)
                let fileSize = value[FileAttributeKey.size] as! UInt64
                let audioFileStream = HWAudioFileStreamKit(fileType: kAudioFileMP3Type, fileSize: UInt64(fileSize))
                
                let lengthPerRead: Int = 10000
                
                while fileSize > 0 {
                    let data = file.readData(ofLength: lengthPerRead)
//                    fileSize -= data.count
                    _ = audioFileStream.parseData(data, error: nil)

                }
                
            } catch _ {
                
            }
            
        }
        
        

//
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

