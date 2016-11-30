//
//  HWAudioQueueKit.swift
//  AudioRecordDemo
//
//  Created by WeiHu on 2016/11/29.
//  Copyright © 2016年 WeiHu. All rights reserved.
//

import UIKit
import AVFoundation

struct MCAudioQueueBuffer {
    var buffer: AudioQueueBufferRef
    
}

class HWAudioQueueKit: NSObject {
    
    private(set) var isAvailable = false
    private(set) var format = AudioStreamBasicDescription()
    var volume: Float = 0.0{
        didSet{
            setVolumeParameter()
        }
    }
    var bufferSize: UInt32 = 0
    private(set) var isRunning: UInt32 = 0
    
    var audioQueue: AudioQueueRef? = nil
    var buffers = Array<MCAudioQueueBuffer>()
    var reusableBuffers = [MCAudioQueueBuffer]()
    
    var started = false
    var playedTime = TimeInterval(){
        didSet{
            guard let audioQueue = audioQueue else {
                self.playedTime = 0
                return
            }
            if format.mSampleRate == 0 {
                self.playedTime = 0
            }
            var time: AudioTimeStamp = AudioTimeStamp()
            let status = AudioQueueGetCurrentTime(audioQueue, nil, &time, nil)
            if status == noErr {
                self.playedTime = time.mSampleTime / format.mSampleRate
            }
            
        }
    }
    fileprivate var mutex = pthread_mutex_t()
    fileprivate var cond = pthread_cond_t()
    
    
    static let MCAudioQueueBufferCount = 2
    override init() {
        super.init()
    }
    
    convenience init(format: AudioStreamBasicDescription, bufferSize: UInt32, macgicCookie: Data) {
        self.init()
        
        self.format = format
        self.volume = 1.0
        self.bufferSize = bufferSize
        self._createAudioOutputQueue(macgicCookie)
        self._mutexInit()
        
    }
    deinit {
        self._disposeAudioOutputQueue()
        self._mutexDestory()
    }
//    // MARK: - error
//    
//    func _error(for status: OSStatus, error outError: Error?) {
//        if status != noErr && outError != nil {
//            outError = Error(domain: NSOSStatusErrorDomain, code: status, userInfo: nil)
//        }
//    }

    func handleAudioQueueOutputCallBack(_ audioQueue: AudioQueueRef, buffer: AudioQueueBufferRef) {
        for i in 0..<buffers.count {
            if buffer == buffers[i].buffer {
                reusableBuffers.append(buffers[i])
            }
        }
        self._mutexSignal()
    }
    
    func handleAudioQueuePropertyCallBack(_ audioQueue: AudioQueueRef, property: AudioQueuePropertyID) {
        if property == kAudioQueueProperty_IsRunning {
            var isRunning: UInt32 = 0
            var size: UInt32 = UInt32(MemoryLayout<UInt32>.size)
            AudioQueueGetProperty(audioQueue, property, &isRunning, &size)
            self.isRunning = isRunning
        }
    }
    func _createAudioOutputQueue(_ magicCookie: Data?) {
     
        let brige_self = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var status = AudioQueueNewOutput(&format, MCAudioQueueOutputCallback, brige_self, nil, nil, 0, &audioQueue)
        if status != noErr {
            self.audioQueue = nil
            return
        }
        guard let audioQueue = audioQueue else {
            return
        }
        status = AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning, MCAudioQueuePropertyCallback, brige_self)
        if status != noErr {
            AudioQueueDispose(audioQueue, true)
            self.audioQueue = nil
            return
        }
        if buffers.count == 0 {
            for _ in 0..<HWAudioQueueKit.MCAudioQueueBufferCount {
                var buffer: AudioQueueBufferRef?
                status = AudioQueueAllocateBuffer(audioQueue, bufferSize, &buffer)
                if status != noErr {
                    AudioQueueDispose(audioQueue, true)
                    self.audioQueue = nil
                }
                
                if let buffer = buffer{
                    let bufferObj = MCAudioQueueBuffer(buffer: buffer)
                    buffers.append(bufferObj)
                    reusableBuffers.append(bufferObj)
                }
            }
        }
        var property: UInt32 = kAudioQueueHardwareCodecPolicy_PreferSoftware
        
        let _ = setProperty(kAudioQueueProperty_HardwareCodecPolicy, dataSize: UInt32(MemoryLayout<UInt32>.size), data: &property, error: nil)
    
        if let magicCookie = magicCookie {
            AudioQueueSetProperty(audioQueue, kAudioQueueProperty_MagicCookie, [UInt8](magicCookie), UInt32(magicCookie.count))
        }
        self.setVolumeParameter()
    }
    
    func _disposeAudioOutputQueue() {
        if let audioQueue = audioQueue {
            AudioQueueDispose(audioQueue, true)
            self.audioQueue = nil
        }
    }

    func _start() -> Bool {
        
        guard let audioQueue = audioQueue else {
            return false
        }
        let status = AudioQueueStart(audioQueue, nil)
        started = status == noErr
        return started
    }

    func resume() -> Bool {
        return _start()
    }

    func pause() -> Bool {
        guard let audioQueue = audioQueue else {
            return false
        }
        let status = AudioQueuePause(audioQueue)
        self.started = false
        return status == noErr
    }

    func reset() -> Bool {
        guard let audioQueue = audioQueue else {
            return false
        }
        let status = AudioQueueReset(audioQueue)
        return status == noErr
    }

    func flush() -> Bool {
        guard let audioQueue = audioQueue else {
            return false
        }
        let status = AudioQueuePause(audioQueue)
        return status == noErr
    }

    func stop(_ immediately: Bool = false) -> Bool {
        
        guard let audioQueue = audioQueue else {
            return false
        }

        let  status = AudioQueueStop(audioQueue, immediately)
    
        self.started = false
        self.playedTime = 0
        return status == noErr
    }

    func play(_ data: Data, packetCount: UInt32, packetDescriptions: UnsafePointer<AudioStreamPacketDescription>?, isEof: Bool) -> Bool {
        if UInt32(data.count) > bufferSize {
            return false
        }
        if reusableBuffers.count == 0 {
            if !started && !self._start() {
                return false
            }
            self._mutexWait()
        }
        guard let audioQueue = audioQueue else {
            return false
        }
        var bufferObj = reusableBuffers.first
        
    
        if bufferObj == nil{
            var buffer: AudioQueueBufferRef?
            let status = AudioQueueAllocateBuffer(audioQueue, bufferSize, &buffer)
            if status == noErr, let buffer = buffer {
                bufferObj = MCAudioQueueBuffer(buffer: buffer)
            }
            else {
                return false
            }
        }else{
            reusableBuffers.remove(at: 0)
        }
        
        memcpy(bufferObj!.buffer.pointee.mAudioData, [UInt8](data), data.count)
        bufferObj!.buffer.pointee.mAudioDataByteSize = UInt32(data.count)
        let status = AudioQueueEnqueueBuffer(audioQueue, bufferObj!.buffer, packetCount, packetDescriptions)
        if status == noErr {
            if reusableBuffers.count == 0 || isEof {
                if !started && !self._start() {
                    return false
                }
            }
        }
        return status == noErr
    }
    func setProperty(_ propertyID: AudioQueuePropertyID, dataSize: UInt32, data: UnsafeRawPointer, error outError: Error?) -> Bool {
        
        guard let audioQueue = audioQueue else {
            return false
        }
        let status = AudioQueueSetProperty(audioQueue, propertyID, data, dataSize)

        return status == noErr
    }

    func getProperty(_ propertyID: AudioQueuePropertyID, dataSize: UnsafeMutablePointer<UInt32>, data: UnsafeMutableRawPointer, error outError: Error?) -> Bool {
        guard let audioQueue = audioQueue else {
            return false
        }
        let status =  AudioQueueGetProperty(audioQueue, propertyID, data, dataSize)
      
        return status == noErr
    }
    func setParameter(_ parameterId: AudioQueueParameterID, value: AudioQueueParameterValue, error outError: Error?) -> Bool {
        
        guard let audioQueue = audioQueue else {
            return false
        }
        
        let status = AudioQueueSetParameter(audioQueue, parameterId, value)
     
        return status == noErr
    }

    func getParameter(_ parameterId: AudioQueueParameterID, value: UnsafeMutablePointer<AudioQueueParameterValue>, error outError: Error?) -> Bool {
        
        guard let audioQueue = audioQueue else {
            return false
        }
        
        let status = AudioQueueGetParameter(audioQueue, parameterId, value)
     
        return status == noErr
    }
  
    func available() -> Bool {
        return audioQueue != nil
    }
    
 
    func setVolumeParameter() {
       let _ = setParameter(kAudioQueueParam_Volume, value: volume, error: nil)
    }

    
    // MARK: - callBack
    
    var MCAudioQueueOutputCallback: AudioQueueOutputCallback =  {(inClientData: UnsafeMutableRawPointer?, inAQ: AudioQueueRef, inBuffer: AudioQueueBufferRef) in
        let audioOutputQueue = unsafeBitCast(inClientData, to: HWAudioQueueKit.self)
        audioOutputQueue.handleAudioQueueOutputCallBack(inAQ, buffer: inBuffer)
    }

    var MCAudioQueuePropertyCallback: AudioQueuePropertyListenerProc =  {(inUserData: UnsafeMutableRawPointer?, inAQ: AudioQueueRef, inID: AudioQueuePropertyID) in
        let audioOutputQueue = unsafeBitCast(inUserData, to: HWAudioQueueKit.self)
        audioOutputQueue.handleAudioQueuePropertyCallBack(inAQ, property: inID)
    }

    // MARK: - mutex
    func _mutexInit() {
        pthread_mutex_init(&mutex, nil)
        pthread_cond_init(&cond, nil)
    }
    func _mutexDestory() {
        pthread_mutex_destroy(&mutex)
        pthread_cond_destroy(&cond)
    }
    func _mutexWait() {
        pthread_mutex_lock(&mutex)
        pthread_cond_wait(&cond, &mutex)
        pthread_mutex_unlock(&mutex)
    }
    func _mutexSignal() {
        pthread_mutex_lock(&mutex)
        pthread_cond_signal(&cond)
        pthread_mutex_unlock(&mutex)
    }
}

extension Array where Element: Equatable {
    
    // Remove first collection element that is equal to the given `object`:
    mutating func remove2(object: Element) {
        if let index = index(of: object) {
            remove(at: index)
        }
    }
}
