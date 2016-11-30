//
//  HWAudioBuffer.swift
//  AudioRecordDemo
//
//  Created by WeiHu on 2016/11/30.
//  Copyright © 2016年 WeiHu. All rights reserved.
//

import UIKit
import AVFoundation

class HWAudioBuffer: NSObject {
    
    var bufferBlockArray = [MCParsedAudioData]()
    var bufferedSize: UInt32 = 0
    
    override init() {
        
    }
    func enqueueData(_ data: MCParsedAudioData) {
        bufferBlockArray.append(data)
        bufferedSize += UInt32((data.data?.count)!)
    }
    
    func enqueue(fromDataArray dataArray: [MCParsedAudioData]) {
        
        for  data in dataArray{
            self.enqueueData(data)
        }
    }
    
    func hasData() -> Bool {
        
        return bufferBlockArray.count > 0
    }
    

    //descriptions needs free
    
    func dequeueData(withSize requestSize: UInt32, packetCount: UnsafeMutablePointer<UInt32>, descriptions: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?) -> Data? {
        
        if requestSize == 0 && bufferBlockArray.count == 0 {
            return nil
        }
        var size = requestSize
        var count: UInt32 = 0
        for index in 0..<bufferBlockArray.count {
            let block = bufferBlockArray[index]
            let dataLength = UInt32(block.data?.count ?? 0)
            if size > dataLength {
                size -= dataLength
            }
            else {
                if size < dataLength {
                    count -= 1
                }
            }
        }
        if count < 0{
            return nil;
        }
        let countTemp: UInt32 = (count >= UInt32(bufferBlockArray.count)) ? UInt32(bufferBlockArray.count) : (count + 1)
        packetCount.pointee = UInt32(count)
        
        if countTemp == 0 {
            return nil
        }
        
        if let descriptions = descriptions {
            descriptions.pointee = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: MemoryLayout<AudioStreamPacketDescription>.size * Int(count))
        }
        var retData = Data()
        for j in 0..<count {
            let block = bufferBlockArray[Int(j)]
            if descriptions != nil, var desc = block.packetDescription {
                desc.mStartOffset = Int64(retData.count)
                (descriptions?.pointee)?[Int(j)] = desc
            }
            retData.append(block.data!)
        }
        bufferBlockArray.removeSubrange(0..<Int(count))
        bufferedSize -= UInt32(retData.count)
        
        return retData
    }
    
    func clean() {
        bufferedSize = 0
        bufferBlockArray.removeAll()
    }
    deinit {
        bufferedSize = 0
        bufferBlockArray.removeAll()
    }
}
