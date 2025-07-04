//
//  AVAudioTimeExtension.swift
//  fantasia
//
//  Created by Jack Heart on 7/19/24.
//

// Taken from AudioKit. MIT License for this code:
//The MIT License (MIT)
//
//Copyright (c) 2016 Aurelius Prochazka
//
//Permission is hereby granted, free of charge, to any person obtaining a copy
//of this software and associated documentation files (the "Software"), to deal
//in the Software without restriction, including without limitation the rights
//to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//copies of the Software, and to permit persons to whom the Software is
//furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in
//all copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//THE SOFTWARE.

import Foundation
import AVFoundation

/// Utility to convert between host time and seconds
private let ticksToSeconds: Double = {
    var tinfo = mach_timebase_info()
    let err = mach_timebase_info(&tinfo)
    let timecon = Double(tinfo.numer) / Double(tinfo.denom)
    return timecon * 0.000000001
}()

/// Utility to convert between seconds to host time.
private let secondsToTicks: Double = {
    var tinfo = mach_timebase_info()
    let err = mach_timebase_info(&tinfo)
    let timecon = Double(tinfo.denom) / Double(tinfo.numer)
    return timecon * 1_000_000_000
}()

public extension AVAudioTime {
    /// AVAudioTime.extrapolateTime fails for host time valid times, use
    /// extrapolateTimeShimmed instead. https://bugreport.apple.com/web/?problemID=34249528
    /// - Parameter anchorTime: AVAudioTIme
    func extrapolateTimeShimmed(fromAnchor anchorTime: AVAudioTime) -> AVAudioTime {
        guard (isSampleTimeValid && sampleRate == anchorTime.sampleRate) || isHostTimeValid,
              !(isSampleTimeValid && isHostTimeValid),
              anchorTime.isSampleTimeValid, anchorTime.isHostTimeValid
        else {
            return self
        }
        if isHostTimeValid, anchorTime.isHostTimeValid {
            let secondsDiff = Double(hostTime.safeSubtract(anchorTime.hostTime)) * ticksToSeconds
            let sampleTime = anchorTime.sampleTime + AVAudioFramePosition(round(secondsDiff * anchorTime.sampleRate))
            let audioTime = AVAudioTime(hostTime: hostTime, sampleTime: sampleTime, atRate: anchorTime.sampleRate)
            return audioTime
        } else {
            let secondsDiff = Double(sampleTime - anchorTime.sampleTime) / anchorTime.sampleRate
            let hostTime = anchorTime.hostTime + secondsDiff / ticksToSeconds
            return AVAudioTime(hostTime: hostTime, sampleTime: sampleTime, atRate: anchorTime.sampleRate)
        }
    }

    /// An AVAudioTime with a valid hostTime representing now.
    static func now() -> AVAudioTime {
        return AVAudioTime(hostTime: mach_absolute_time())
    }

    /// Returns an AVAudioTime offset by seconds.
    func offset(seconds: Double) -> AVAudioTime {
        if isSampleTimeValid, isHostTimeValid {
            return AVAudioTime(hostTime: hostTime + seconds / ticksToSeconds,
                               sampleTime: sampleTime + AVAudioFramePosition(seconds * sampleRate),
                               atRate: sampleRate)
        } else if isHostTimeValid {
            return AVAudioTime(hostTime: hostTime + seconds / ticksToSeconds)
        } else if isSampleTimeValid {
            return AVAudioTime(sampleTime: sampleTime + AVAudioFramePosition(seconds * sampleRate),
                               atRate: sampleRate)
        }
        return self
    }

    /// The time in seconds between receiver and otherTime.
    func timeIntervalSince(otherTime: AVAudioTime) -> Double? {
        if isHostTimeValid, otherTime.isHostTimeValid {
            return Double(hostTime.safeSubtract(otherTime.hostTime)) * ticksToSeconds
        }
        if isSampleTimeValid, otherTime.isSampleTimeValid {
            return Double(sampleTime - otherTime.sampleTime) / sampleRate
        }
        if isSampleTimeValid, isHostTimeValid {
            let completeTime = otherTime.extrapolateTimeShimmed(fromAnchor: self)
            return Double(sampleTime - completeTime.sampleTime) / sampleRate
        }
        if otherTime.isHostTimeValid, otherTime.isSampleTimeValid {
            let completeTime = extrapolateTimeShimmed(fromAnchor: otherTime)
            return Double(completeTime.sampleTime - otherTime.sampleTime) / sampleRate
        }
        return nil
    }

    /// Convert an AVAudioTime object to seconds with a hostTime reference
    func toSeconds(hostTime time: UInt64) -> Double {
        guard isHostTimeValid else { return 0 }
        return AVAudioTime.seconds(forHostTime: hostTime - time)
    }

    /// Convert seconds to AVAudioTime with a hostTime reference -- time must be > 0
    class func secondsToAudioTime(hostTime: UInt64, time: Double) -> AVAudioTime {
        // Find the conversion factor from host ticks to seconds
        var timebaseInfo = mach_timebase_info()
        mach_timebase_info(&timebaseInfo)
        let hostTimeToSecFactor = Double(timebaseInfo.numer) / Double(timebaseInfo.denom) / Double(NSEC_PER_SEC)
        let out = AVAudioTime(hostTime: hostTime + UInt64(time / hostTimeToSecFactor))
        return out
    }
}

/// Addition
/// - Parameters:
///   - left: Left Hand Side
///   - right: RIght Hand Side
public func + (left: AVAudioTime, right: Double) -> AVAudioTime {
    return left.offset(seconds: right)
}

/// Addition
/// - Parameters:
///   - left: Left Hand Side
///   - right: RIght Hand Side
public func + (left: AVAudioTime, right: Int) -> AVAudioTime {
    return left.offset(seconds: Double(right))
}

/// Subtraction
/// - Parameters:
///   - left: Left Hand Side
///   - right: RIght Hand Side
public func - (left: AVAudioTime, right: Double) -> AVAudioTime {
    return left.offset(seconds: -right)
}

/// Subtraction
/// - Parameters:
///   - left: Left Hand Side
///   - right: RIght Hand Side
public func - (left: AVAudioTime, right: Int) -> AVAudioTime {
    return left.offset(seconds: Double(-right))
}

private extension UInt64 {
    func safeSubtract(_ other: UInt64) -> Int64 {
        return self > other ? Int64(self - other) : -Int64(other - self)
    }

    static func + (left: UInt64, right: Double) -> UInt64 {
        return right >= 0 ? left + UInt64(right) : left - UInt64(-right)
    }
}
