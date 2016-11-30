//
//  HWAudioLocalKit.swift
//  AudioRecordDemo
//
//  Created by WeiHu on 2016/11/25.
//  Copyright © 2016年 WeiHu. All rights reserved.
//

import UIKit
import AVFoundation
import AudioToolbox

enum MCSAPStatus {
    case Stopped
    case Playing
    case Waiting
    case Paused
    case Flushing

}

class HWAudioLocalPlayerKit: NSObject {
    fileprivate var mutex = pthread_mutex_t()
    fileprivate var cond = pthread_cond_t()
    
    fileprivate var thread: Thread!
    fileprivate var status: MCSAPStatus = MCSAPStatus.Stopped
    fileprivate var fileSize: UInt64 = 0
    
    fileprivate var filePath: String = ""
    fileprivate var fileType: AudioFileTypeID = AudioFileTypeID()
    
    var offset: UInt64 = 0
    var fileHandler: FileHandle!
    var bufferSize: UInt64 = 0
    var buffer: HWAudioBuffer = HWAudioBuffer()
    
    var audioFileStream: HWAudioFileStreamKit = HWAudioFileStreamKit()
    var audioQueue: HWAudioQueueKit?
    var started: Bool = false
    var pauseRequired: Bool = false
    var stopRequired: Bool = false
    var pausedByInterrupt: Bool = false
    var failed: Bool = false
    var isPlayingOrWaiting: Bool = false{
        didSet{
            isPlayingOrWaiting = self.status == .Waiting || self.status == .Playing || self.status == .Flushing
        }
    }
    
    var duration: TimeInterval = 0{
        didSet{
            duration = audioFileStream.duration
        }
    }
    
    var seekRequired: Bool = false
    var seekTime = TimeInterval()
    var timingOffset = TimeInterval()
    
    init(filePath: String, fileType: AudioFileTypeID) {
        self.filePath = filePath
        self.fileType = fileType
        
        do {
            let value: [FileAttributeKey : Any] = try FileManager.default.attributesOfItem(atPath: filePath)
            fileSize = value[FileAttributeKey.size] as! UInt64
            
            if let fileHandler = FileHandle(forReadingAtPath: filePath) , fileSize > 0 {
                self.fileHandler = fileHandler
            }else{
                
            }
            
        } catch _ {
            
        }
    
    }

    func createAudioQueue() -> Bool {
        
        guard let audioQueue = audioQueue else {
            return true
        }

        let duration = self.duration
        let audioDataByteCount: UInt64 = audioFileStream.audioDataByteCount
        self.bufferSize = 0
        if duration != 0 {
            self.bufferSize = UInt64(0.2 / duration) * audioDataByteCount
        }
        if bufferSize > 0 {
            let format = audioFileStream.format
            if let magicCookie = audioFileStream.fetchMagicCookie(){
                self.audioQueue = HWAudioQueueKit(format: format, bufferSize: UInt32(bufferSize), macgicCookie: magicCookie)
            }
            if !audioQueue.available() {
                self.audioQueue = nil
                return false
            }
        }
        return true
    }
    func threadMain() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
            
            audioFileStream = HWAudioFileStreamKit(fileType: fileType, fileSize: fileSize)
            audioFileStream.delegate = self
        } catch _ {
            
        }
        var isEof: Bool = false
        while self.status != .Stopped  ,started {
            
            if offset < fileSize && (!audioFileStream.isReadyToProducePackets || UInt64(buffer.bufferedSize)<bufferSize || !(audioQueue != nil)) {
                var data = fileHandler.readData(ofLength: 1000)
                offset += UInt64(data.count)
                if offset >= fileSize {
                    isEof = true
                }
                let _ =  audioFileStream.parseData(data, error: nil)
                if audioFileStream.isReadyToProducePackets {
                    if !self.createAudioQueue() {
                        break
                    }
                    if !(audioQueue != nil) {
                        continue
                    }
                    if self.status == .Flushing && audioQueue!.isRunning == 0 {
                        break
                    }
                    
                    if UInt64(buffer.bufferedSize) >= bufferSize || isEof {
                        
                        var packetCount: UInt32 = 0
                        var desces: UnsafeMutablePointer<AudioStreamPacketDescription>? = nil
                        let data = buffer.dequeueData(withSize: UInt32(bufferSize), packetCount: &packetCount, descriptions: &desces)
                        if packetCount != 0 {
                            
                            self.failed = !(audioQueue?.play(data!, packetCount: packetCount, packetDescriptions: desces, isEof: isEof))!
                            free(desces)
                            if failed {
                                
                            }
                            if !buffer.hasData() && isEof && audioQueue!.isRunning == 0 {
                                let _ = audioQueue?.stop(false)
                                
                            }
                        }
                    }
                    else if isEof {
                        //wait for end
                        if !buffer.hasData() && audioQueue!.isRunning == 0 {
                            let _ = audioQueue?.stop(false)
                        }
                    }
                    else {
                        
                    }
                    
                }
               
            }
        }

    }
    //开始播放
    func startPlay() {
        if !started {
            self.started = true
            self._mutexInit()
            self.thread = Thread(target: self, selector: #selector(HWAudioLocalPlayerKit.threadMain), object: nil)
            thread.start()
        }
        else {
            if status == .Paused || pauseRequired {
                self.pausedByInterrupt = false
                self.pauseRequired = false
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
                } catch _ {
                    
                }
            }
        }
    }
    //停止播放
    func stopPlay() {
        
    }
    //终端播放
    func pausePlay() {
        
    }

    // MARK: - mutex
    fileprivate func _mutexInit() {
        pthread_mutex_init(&mutex, nil)
        pthread_cond_init(&cond, nil)
    }
    fileprivate func _mutexDestory() {
        pthread_mutex_destroy(&mutex)
        pthread_cond_destroy(&cond)
    }
    fileprivate func _mutexWait() {
        pthread_mutex_lock(&mutex)
        pthread_cond_wait(&cond, &mutex)
        pthread_mutex_unlock(&mutex)
    }
    fileprivate func _mutexSignal() {
        pthread_mutex_lock(&mutex)
        pthread_cond_signal(&cond)
        pthread_mutex_unlock(&mutex)
    }
}
extension HWAudioLocalPlayerKit: HWAudioFileStreamDelegate{
    func audioFileStream(_: HWAudioFileStreamKit, audioDataParsed: Array<Any>) {
        
    }
}
