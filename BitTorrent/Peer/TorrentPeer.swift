//
//  TorrentPeer.swift
//  BitTorrent
//
//  Created by Ben Davis on 09/07/2017.
//  Copyright © 2017 Ben Davis. All rights reserved.
//

import Foundation

protocol TorrentPeerDelegate: class {
    func peerCompletedHandshake(_ sender: TorrentPeer)
    func peerLost(_ sender: TorrentPeer)
    func peer(_ sender: TorrentPeer, gotPieceAtIndex index: Int, piece: Data)
    func peer(_ sender: TorrentPeer, failedToGetPieceAtIndex index: Int)
}

class TorrentPeer {
    
    var enableLogging = false {
        didSet {
            communicator.enableLogging = enableLogging
        }
    }
    
    static let maximumNumberOfPendingBlockRequests = 20
    
    weak var delegate: TorrentPeerDelegate?
    
    let peerInfo: TorrentPeerInfo
    private let communicator: TorrentPeerCommunicator
    
    // Peer state
    private(set) var peerChoked: Bool = true
    private(set) var peerInterested: Bool = false
    private(set) var amChokedToPeer: Bool = true
    private(set) var amInterestedInPeer: Bool = false
    private(set) var currentProgress: BitField
    
    var connected: Bool = false
    
    private var downloadPieceRequests: [Int: TorrentPieceDownloadBuffer] = [:]
    private var numberOfPendingRequests = 0
    
    init(peerInfo: TorrentPeerInfo, bitFieldSize: Int, communicator: TorrentPeerCommunicator) {
        self.peerInfo = peerInfo
        self.communicator = communicator
        self.currentProgress = BitField(size: bitFieldSize)
        communicator.delegate = self
    }
    
    convenience init(peerInfo: TorrentPeerInfo, infoHash: Data, bitFieldSize: Int) {
        let communicator = TorrentPeerCommunicator(peerInfo: peerInfo, infoHash: infoHash)
        self.init(peerInfo: peerInfo, bitFieldSize: bitFieldSize, communicator: communicator)
    }
    
    private var handshakeData: (clientId: Data, bitField: BitField)?
    
    func connect(withHandshakeData handshakeData:(clientId: Data, bitField: BitField)) throws {
        self.handshakeData = handshakeData
        try communicator.connect()
        connected = true
    }
    
    func downloadPiece(atIndex index: Int, size: Int) {
        
        let downloadBuffer = TorrentPieceDownloadBuffer(index: index, size: size)
        downloadPieceRequests[index] = downloadBuffer
        
        if !amInterestedInPeer {
            amInterestedInPeer = true
            communicator.sendInterested()
        }
        
        if !peerChoked {
            requestNextBlock()
        }
    }
    
    private func requestNextBlock() {
        if numberOfPendingRequests < TorrentPeer.maximumNumberOfPendingBlockRequests {
            
            guard let pieceRequest = downloadPieceRequests.values.first else { return }
            guard let blockRequest = pieceRequest.nextDownloadBlock() else { return }
            
            numberOfPendingRequests += 1
            
            communicator.sendRequest(fromPieceAtIndex: blockRequest.piece,
                                     begin: blockRequest.begin,
                                     length: blockRequest.length)
            requestNextBlock()
        }
    }
    
    private func killAllDownloads() {
        for downloadPieceRequest in downloadPieceRequests {
            delegate?.peer(self, failedToGetPieceAtIndex: downloadPieceRequest.value.index)
        }
        downloadPieceRequests.removeAll()
    }
}

extension TorrentPeer: TorrentPeerCommunicatorDelegate {
    
    func peerConnected(_ sender: TorrentPeerCommunicator) {
        
        if enableLogging { print("Peer socket connected (\(peerInfo.ip):\(peerInfo.port)") }
        
        guard let (clientId, bitField) = handshakeData else { return }
        
        communicator.sendHandshake(for: clientId) { [weak self] in
            self?.communicator.sendBitField(bitField)
        }
    }
    
    func peerLost(_ sender: TorrentPeerCommunicator) {
        killAllDownloads()
        delegate?.peerLost(self)
        connected = false
    }
    
    func peerSentHandshake(_ sender: TorrentPeerCommunicator, sentHandshakeWithPeerId peerId: Data, onDHT: Bool) {
        delegate?.peerCompletedHandshake(self)
    }
    
    func peerSentKeepAlive(_ sender: TorrentPeerCommunicator) {
        
    }
    
    func peerBecameChoked(_ sender: TorrentPeerCommunicator) {
        peerChoked = true
        killAllDownloads()
    }
    
    func peerBecameUnchoked(_ sender: TorrentPeerCommunicator) {
        peerChoked = false
        requestNextBlock()
    }
    
    func peerBecameInterested(_ sender: TorrentPeerCommunicator) {
        peerInterested = true
    }
    
    func peerBecameUninterested(_ sender: TorrentPeerCommunicator) {
        peerInterested = false
    }
    
    func peer(_ sender: TorrentPeerCommunicator, hasPiece piece: Int) {
        currentProgress.set(at: piece)
    }
    
    func peer(_ sender: TorrentPeerCommunicator, hasBitField bitField: BitField) {
        currentProgress = bitField
    }
    
    func peer(_ sender: TorrentPeerCommunicator, requestedPiece index: Int, begin: Int, length: Int) {
        
    }
    
    func peer(_ sender: TorrentPeerCommunicator, sentPiece index: Int, begin: Int, block: Data) {
        guard let downloadPieceBuffer = downloadPieceRequests[index] else { return }
        numberOfPendingRequests -= 1
        downloadPieceBuffer.gotBlock(block, begin: begin)
        if downloadPieceBuffer.isComplete, let piece = downloadPieceBuffer.piece {
            delegate?.peer(self, gotPieceAtIndex: index, piece: piece)
        }
        requestNextBlock()
    }
    
    func peer(_ sender: TorrentPeerCommunicator, cancelledRequestedPiece index: Int, begin: Int, length: Int) {
        
    }
    
    func peer(_ sender: TorrentPeerCommunicator, onDHTPort port: Int) {
        
    }
    
    func peerSentMalformedMessage(_ sender: TorrentPeerCommunicator) {
        
    }
}

extension TorrentPeer {
    
    class func makePeerId() -> Data {
        var peerId = "-BD0000-"
        
        for _ in 0...11 {
            let asciiCharacters = [" ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"]
            let numberOfAscii = asciiCharacters.count
            let randomIndex = arc4random() % UInt32(numberOfAscii)
            let random = asciiCharacters[Int(randomIndex)]
            peerId += random
        }
        
        return peerId.data(using: .utf8)!
    }
}