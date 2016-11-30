//
//  HWAudioKit.swift
//  AudioRecordDemo
//
//  Created by WeiHu on 2016/11/25.
//  Copyright © 2016年 WeiHu. All rights reserved.
//

import UIKit
import AudioToolbox
import AVFoundation

enum StreamError: Error {
    case invalidSelection                    //选择无效
    case insufficientFunds(coinsNeeded: Int) //金额不足
    case outOfStock                          //缺货
}

@objc protocol HWAudioFileStreamDelegate {
    @objc func audioFileStream(_: HWAudioFileStreamKit, audioDataParsed: Array<Any>)
    @objc optional func audioFileStreamReadyToProducePackets(audioFileStream: HWAudioFileStreamKit)
}
@objc class MCParsedAudioData: NSObject{
    fileprivate(set) var data: Data?
    fileprivate(set) var packetDescription: AudioStreamPacketDescription?
    
    
    override init() {
        super.init()
    }
    convenience init(bytes: UnsafeRawPointer, packetDescription: AudioStreamPacketDescription?) {
        self.init()
        if let packetDescription = packetDescription{
            self.data = Data(bytes: bytes, count: Int(packetDescription.mDataByteSize))
            self.packetDescription = packetDescription
        }
    }
}

final class HWAudioFileStreamKit: NSObject {
    
    private(set) var fileType = AudioFileTypeID()
    private(set) var isAvailable = false
    private(set) var isReadyToProducePackets = false
    weak var delegate: HWAudioFileStreamDelegate?
    private(set) var format = AudioStreamBasicDescription()
    private(set) var fileSize: UInt64 = 0
    private(set) var duration = TimeInterval()
    private(set) var bitRate: UInt32 = 0
    private(set) var maxPacketSize: UInt32 = 0
    private(set) var audioDataByteCount: UInt64 = 0
    
    fileprivate var discontinuous: Bool = false
    fileprivate var audioFileStreamID: AudioFileStreamID?
    fileprivate var dataOffset: Int64 = 0
    fileprivate var packetDuration: TimeInterval = 0
    fileprivate var processedPacketsCount: UInt32 = 0
    fileprivate var processedPacketsSizeTotal: UInt32 = 0
    
    fileprivate var packetOffset: UInt32 = 0
 
    static let BitRateEstimationMaxPackets: UInt32 = 5000
    static let BitRateEstimationMinPackets: UInt32 = 10
    
    override init() {
        super.init()
    }
    
    convenience init(fileType: AudioFileTypeID, fileSize: UInt64) {
        self.init()
        
        self.fileType = fileType
        self.fileSize = fileSize
        
        let status = AudioFileStreamOpen(bridge(obj: self), MCSAudioFileStreamPropertyListener, MCAudioFileStreamPacketsCallBack, fileType, &audioFileStreamID)
        if status != noErr {
            return
        }
    }
    func calculateDuration() {
        if fileSize > 0 && bitRate > 0 {
            duration = TimeInterval((audioDataByteCount * 8) / UInt64(bitRate))
        }
        print(duration)
    }
    func calculatepPacketDuration() {
        if format.mSampleRate > 0{
            packetDuration = Float64(format.mFramesPerPacket)/format.mSampleRate
        }
    }
    
    func calculateBitRate() {
        if packetDuration > 0 && processedPacketsCount > HWAudioFileStreamKit.BitRateEstimationMinPackets && processedPacketsCount <= HWAudioFileStreamKit.BitRateEstimationMaxPackets{
            let averagePacketByteSize = processedPacketsSizeTotal / processedPacketsCount;
            bitRate = UInt32(8.0 * Double(averagePacketByteSize) / packetDuration)
        }
    }
    fileprivate func handleAudioFileStreamProperty(propertyID: AudioFileStreamPropertyID)  {
        
        guard let audioFileStreamID = audioFileStreamID else {
            return
        }
        switch propertyID {
        case kAudioFileStreamProperty_ReadyToProducePackets:
            //获得文件包a打下小
            isReadyToProducePackets = true
            discontinuous = true

            var sizeOfUInt32: UInt32 = UInt32(MemoryLayout<UInt32>.size)
            var status = AudioFileStreamGetProperty(audioFileStreamID, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &maxPacketSize)
            if status != noErr || maxPacketSize == 0 {
                status = AudioFileStreamGetProperty(audioFileStreamID, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32, &maxPacketSize)
            }
            
        case kAudioFileStreamProperty_DataOffset:
            //获取音频实际数据在文件中的位置
            var offsetSize = UInt32(MemoryLayout<Int64>.size)
            AudioFileStreamGetProperty(audioFileStreamID, kAudioFileStreamProperty_DataOffset, &offsetSize, &dataOffset);
            audioDataByteCount = fileSize - UInt64(dataOffset)
            calculateDuration()
            
        case kAudioFileStreamProperty_DataFormat:
            // 音频的基本数据
            var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            AudioFileStreamGetProperty(audioFileStreamID, kAudioFileStreamProperty_DataFormat, &asbdSize, &format);
            calculatepPacketDuration()
            
        case kAudioFileStreamProperty_FormatList:
            break
        default:
            break
        }
    }
    
    fileprivate func handleAudioFileStreamPackets(packets: UnsafeRawPointer, numberOfBytes: UInt32, numberOfPackets: UInt32, packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>)  {
        //分离音频帧
        var parsedDataArray: [MCParsedAudioData] = [MCParsedAudioData]()
        let packets_pointee = packets.assumingMemoryBound(to: Int.self).pointee
        for index in 0..<numberOfPackets {
            
            let packetOffset: Int64 = packetDescriptions[Int(index)].mStartOffset
            var reslut: Int = Int(packetOffset) + packets_pointee
            let parsedData = MCParsedAudioData(bytes: &reslut, packetDescription: packetDescriptions[Int(index)])
            parsedDataArray.append(parsedData)
            
            if (processedPacketsCount < HWAudioFileStreamKit.BitRateEstimationMaxPackets)
            {
                processedPacketsSizeTotal += packetDescriptions[Int(index)].mDataByteSize;
                processedPacketsCount += 1;
                calculateBitRate()
                calculateDuration()
            }
        }
    }
    
    func parseData(_ data: Data, error: Error?) -> Bool {
        
        let status = AudioFileStreamParseBytes(audioFileStreamID!, UInt32(data.count), [UInt8](data), discontinuous ? AudioFileStreamParseFlags(rawValue: 1) : AudioFileStreamParseFlags(rawValue: 0))
      
        return status == noErr
    }
    
    func seek(toTime time: TimeInterval) -> Int64 {
        
        return 0
    }
    
    func fetchMagicCookie() -> Data? {
        var cookieSize: UInt32 = 0
        var writable: DarwinBoolean = false
        guard let audioFileStreamID = audioFileStreamID else {
            return nil
        }
        var status = AudioFileStreamGetPropertyInfo(audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
        if (status != noErr)
        {
            return nil;
        }
        let cookieData = malloc(Int(cookieSize))
        status = AudioFileStreamGetProperty(audioFileStreamID, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData!);
        if (status != noErr)
        {
            return nil;
        }
        let cookie = Data(bytes: cookieData!, count: Int(cookieSize))
        free(cookieData);
        
        return cookie
    }
    
    func close() {
        
    }
    
    
    fileprivate var MCSAudioFileStreamPropertyListener: AudioFileStream_PropertyListenerProc = {(inClientData: UnsafeMutableRawPointer, inAudioFileStream: AudioFileStreamID, inPropertyID: AudioFileStreamPropertyID, ioFlags: UnsafeMutablePointer<AudioFileStreamPropertyFlags>)in
        let inClientData: HWAudioFileStreamKit = unsafeBitCast(inClientData, to: HWAudioFileStreamKit.self)
        inClientData.handleAudioFileStreamProperty(propertyID: inPropertyID)
    }
    fileprivate var MCAudioFileStreamPacketsCallBack: AudioFileStream_PacketsProc = {(inClientData: UnsafeMutableRawPointer, inNumberBytes: UInt32, inNumberPackets:  UInt32, inInputData: UnsafeRawPointer, inPacketDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>) in
        
        let inClientData: HWAudioFileStreamKit = unsafeBitCast(inClientData, to: HWAudioFileStreamKit.self)
        inClientData.handleAudioFileStreamPackets(packets: inInputData,
                                            numberOfBytes: inNumberBytes,
                                          numberOfPackets: inNumberPackets,
                                       packetDescriptions: inPacketDescriptions)

    }
    
    func bridge<T : AnyObject>(obj : T) -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(Unmanaged.passUnretained(obj).toOpaque())
    }
    
    func bridge<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
        return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
    }
    
    func bridgeRetained<T : AnyObject>(obj : T) -> UnsafeRawPointer {
        return UnsafeRawPointer(Unmanaged.passRetained(obj).toOpaque())
    }
    
    func bridgeTransfer<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
        return Unmanaged<T>.fromOpaque(ptr).takeRetainedValue()
    }
    
}


