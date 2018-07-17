//
//  TransferTransactionHelper.swift
//  NemSwift
//
//  Created by Kazuya Okada on 2017/11/22.
//  Copyright © 2017年 OpenApostille. All rights reserved.
//

import Foundation

public struct TransferMosaic {
    public let namespace: String
    public let mosaic: String
    public let quantity: UInt64
    public let supply: UInt64
    public let divisibility: Int

    public init(namespace: String, mosaic: String, quantity: UInt64, supply: UInt64, divisibility: Int) {
        self.namespace = namespace
        self.mosaic = mosaic
        self.quantity = quantity
        self.supply = supply
        self.divisibility = divisibility
    }
}

public class TransferTransactionHelper: TransactionHelper {
    
    public enum MessageType: UInt32 {
        case Plain = 1
        case Secure = 2
    }
    
    public let recipientAddress: String
    public let amount: UInt64
    public let messageType: MessageType
    public let message: String
    public let mosaics: [TransferMosaic]?
    
    init(publicKey: [UInt8], network: Network, recipientAddress: String, amount: UInt64, messageType: MessageType, message: String, mosaics: [TransferMosaic]?) {
        self.recipientAddress = recipientAddress
        self.amount = amount
        self.messageType = messageType
        self.message = message
        self.mosaics = mosaics
        
        super.init(type: .Transfer, publicKey: publicKey, network: network)
    }
    
    public static func generateTransferRequestAnnounce(publicKey: [UInt8], network: Network, recipientAddress: String, amount: UInt64, messageType: MessageType, message: String) -> [UInt8] {
        let announce = TransferTransactionHelper(publicKey: publicKey, network: network,
                                                 recipientAddress: recipientAddress, amount: amount,
                                                 messageType: messageType, message: message, mosaics: nil)
        return announce.generateRequestAnnounce()
    }
    
    public static func generateMosaicTransferRequestAnnounce(publicKey: [UInt8], network: Network, recipientAddress: String, mosaics: [TransferMosaic], messageType: MessageType, message: String) -> [UInt8] {
        
        let amount = (UInt64)(1_000_000)
        
        let announce = TransferTransactionHelper(publicKey: publicKey, network: network, recipientAddress: recipientAddress, amount: amount, messageType: messageType, message: message, mosaics: mosaics)
        
        return announce.generateRequestAnnounce()
    }
    
    public func generateRequestAnnounce() -> [UInt8] {
        let commonField = generateCommonTransactionField(transactionFee: transferFee())
        
        return commonField +
            ConvertUtil.toByteArrayWithLittleEndian(UInt32(recipientAddress.count)) +
            Array(recipientAddress.utf8) as [UInt8] +
            ConvertUtil.toByteArrayWithLittleEndian(amount) +
            messageBytes() +
            mosaicBytes()
    }
    
    private func messagePayloadBytes() -> [UInt8] {
        // TODO: 暗号化は後で対応する
        return Array(message.utf8)
    }
    
    private func messageLength() -> UInt32 {
        return UInt32(4) + UInt32(4) + (UInt32)(messagePayloadBytes().count)
    }
    
    private func transferFee() -> UInt64 {
        if mosaics?.isEmpty ?? true{
            return xemTransferFee() + messageTransferFee()
        } else {
            return mosaicTransferFee() + messageTransferFee()
        }
    }
    
    private func xemTransferFee() -> UInt64 {
        return UInt64(max(50_000, min(((amount / 10_000_000_000) * 50_000), (UInt64)(TransactionHelper.maximumXemTransferFee))))
    }
    
    private func messageTransferFee() -> UInt64 {
        let count = messagePayloadBytes().count
        return (UInt64)(count > 0 ? 50_000 * UInt(1 + message.lengthOfBytes(using: .utf8) / 32) : 0)
    }

    private func mosaicTransferFee() -> UInt64 {
        guard let mosaics = mosaics else {
            return 0
        }
        var mosaicTransferFeeTotal: UInt64 = 0
        mosaics.forEach { mosaic in
            if ( mosaic.divisibility == 0 && mosaic.supply < 10_000 ) { // small buisiness mosaic
                mosaicTransferFeeTotal += 50_000
            } else {
                let maxMosaicQuantity: Int64 = 9_000_000_000_000_000
                let totalMosaicQuantity = Double(mosaic.supply) * pow(10.0, Double(mosaic.divisibility))
                let supplyRelatedAdjustment = Int64(floor(0.8 * log(Double(maxMosaicQuantity) / totalMosaicQuantity)))


                let xemEquivalent = NSDecimalNumber(value: 8_999_999_999 as Int64).multiplying(by: NSDecimalNumber(value: mosaic.quantity)).dividing(by: NSDecimalNumber(value: totalMosaicQuantity))

                let microNemEquivalent = Int64(xemEquivalent.multiplying(by: NSDecimalNumber(value: pow(10.0, 6.0))).doubleValue)
                let microNemEquivalentFee =  Int64(max(50_000, min(((microNemEquivalent / 10_000_000_000) * 50_000), Int64(TransactionHelper.maximumXemTransferFee))))

                let calculatedFee: Int64 = microNemEquivalentFee - 50_000 * supplyRelatedAdjustment
                mosaicTransferFeeTotal += UInt64(max(50_000, calculatedFee))
            }
        }
        return max(50_000, mosaicTransferFeeTotal)
    }




    private func messageBytes() -> [UInt8] {
        if (message.isEmpty) {
            return ConvertUtil.toByteArrayWithLittleEndian(UInt32(0))
        } else {
            return ConvertUtil.toByteArrayWithLittleEndian(messageLength()) +
                ConvertUtil.toByteArrayWithLittleEndian(messageType.rawValue) +
                ConvertUtil.toByteArrayWithLittleEndian((UInt32)(messagePayloadBytes().count)) +
                messagePayloadBytes()
        }
    }
    
    private func mosaicBytes() -> [UInt8] {
        guard let mosaics = mosaics else {
            return ConvertUtil.toByteArrayWithLittleEndian(UInt32(0))
        }
        
        var mosaicsBytes: [UInt8]?
        let mosaicNumBytes = ConvertUtil.toByteArrayWithLittleEndian(UInt32(mosaics.count))
        
        for mosaic in mosaics {
            let mosaicNameSpaceIdBytes = Array(mosaic.namespace.utf8) as [UInt8]
            let mosaicNameBytes = Array(mosaic.mosaic.utf8) as [UInt8]
            let mosaicIdStructLength = 4 + mosaicNameSpaceIdBytes.count + 4 + mosaicNameBytes.count
            let mosaicStructLength = 4 + mosaicIdStructLength + 8
        
            let tmp = ConvertUtil.toByteArrayWithLittleEndian((UInt32)(mosaicStructLength)) +
            ConvertUtil.toByteArrayWithLittleEndian((UInt32)(mosaicIdStructLength)) +
            ConvertUtil.toByteArrayWithLittleEndian((UInt32)(mosaicNameSpaceIdBytes.count)) +
            mosaicNameSpaceIdBytes +
            ConvertUtil.toByteArrayWithLittleEndian((UInt32)(mosaicNameBytes.count)) +
            mosaicNameBytes +
            ConvertUtil.toByteArrayWithLittleEndian(mosaic.quantity)
            
            if (mosaicsBytes == nil) {
                mosaicsBytes = tmp
            } else {
                mosaicsBytes = mosaicsBytes! + tmp
            }
        }
        
        return mosaicNumBytes + mosaicsBytes!
    }
}