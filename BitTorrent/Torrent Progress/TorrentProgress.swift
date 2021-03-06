//
//  TorrentProgress.swift
//  BitTorrent
//
//  Created by Ben Davis on 23/07/2017.
//  Copyright © 2017 Ben Davis. All rights reserved.
//

import Foundation

public struct TorrentProgress {
    
    public private(set) var bitField: BitField
    private var piecesBeingDownloaded: [Int] = []
    
    public private(set) var downloaded: Int = 0
    
    public var remaining: Int {
        return bitField.size - downloaded
    }
    
    public var complete: Bool {
        return downloaded == bitField.size
    }
    
    public var percentageComplete: Float {
        return Float(downloaded) / Float(bitField.size)
    }
    
    init(size: Int) {
        self.bitField = BitField(size: size)
    }
    
    init(bitField: BitField) {
        self.bitField = bitField
        for (_, isSet) in bitField where isSet {
            downloaded += 1
        }
    }
    
    func isCurrentlyDownloading(piece: Int) -> Bool {
        return piecesBeingDownloaded.contains(piece)
    }
    
    func hasPiece(_ index: Int) -> Bool {
        return bitField.isSet(at: index)
    }
    
    mutating func setCurrentlyDownloading(piece: Int) {
        piecesBeingDownloaded.append(piece)
    }
    
    mutating func setLostPiece(_ piece: Int) {
        if let index = piecesBeingDownloaded.index(of: piece) {
            piecesBeingDownloaded.remove(at: index)
        }
    }
    
    mutating func finishedDownloading(piece: Int) {
        if let index = piecesBeingDownloaded.index(of: piece) {
            piecesBeingDownloaded.remove(at: index)
            downloaded += 1
            bitField.set(at: piece)
        }
    }
}
