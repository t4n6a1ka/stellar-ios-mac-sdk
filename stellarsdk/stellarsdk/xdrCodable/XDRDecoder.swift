//
//  XDRDecoder.swift
//  stellarsdk
//
//  Created by Razvan Chelemen on 08/02/2018.
//  Copyright © 2018 Soneso. All rights reserved.
//

import Foundation

/// A protocol for types which can be decoded from binary.
public protocol XDRDecodable: Decodable {
    init(fromBinary decoder: XDRDecoder) throws
    init(fromBinary decoder: XDRDecoder, count: Int) throws
}

/// Provide a default implementation which calls through to `Decodable`. This
/// allows `XDRDecodable` to use the `Decodable` implementation generated by the
/// compiler.
public extension XDRDecodable {
    public init(fromBinary decoder: XDRDecoder) throws {
        try self.init(from: decoder)
    }
    
    public init(fromBinary decoder: XDRDecoder, count: Int) throws {
        try self.init(fromBinary: decoder)
    }
}

/// The actual binary decoder class.
public class XDRDecoder {
    fileprivate let data: [UInt8]
    fileprivate var cursor = 0
    
    public init(data: [UInt8]) {
        self.data = data
    }
}

/// A convenience function for creating a decoder from some data and decoding it
/// into a value all in one shot.
public extension XDRDecoder {
    static func decode<T: XDRDecodable>(_ type: T.Type, data: [UInt8]) throws -> T {
        return try XDRDecoder(data: data).decode(T.self)
    }
    
    static func decode<T: XDRDecodable>(_ type: T.Type, data: Data) throws -> T {
        return try XDRDecoder(data: data.map { $0 }).decode(T.self)
    }
}

/// The error type.
public extension XDRDecoder {
    /// All errors which `XDRDecoder` itself can throw.
    enum Error: Swift.Error {
        /// The decoder hit the end of the data while the values it was decoding expected
        /// more.
        case prematureEndOfData
        
        /// Attempted to decode a type which is `Decodable`, but not `XDRDecodable`. (We
        /// require `XDRDecodable` because `XDRDecoder` doesn't support full keyed
        /// coding functionality.)
        case typeNotConformingToXDRDecodable(Decodable.Type)
        
        /// Attempted to decode a type which is not `Decodable`.
        case typeNotConformingToDecodable(Any.Type)
        
        /// Attempted to decode an `Int` which can't be represented. This happens in 32-bit
        /// code when the stored `Int` doesn't fit into 32 bits.
        case intOutOfRange(Int64)
        
        /// Attempted to decode a `UInt` which can't be represented. This happens in 32-bit
        /// code when the stored `UInt` doesn't fit into 32 bits.
        case uintOutOfRange(UInt64)
        
        /// Attempted to decode a `Bool` where the byte representing it was not a `1` or a
        /// `0`.
        case boolOutOfRange(UInt32)
        
        /// Attempted to decode a `String` but the encoded `String` data was not valid
        /// UTF-8.
        case invalidUTF8([UInt8])
    }
}

/// Methods for decoding various types.
public extension XDRDecoder {
    func decode(_ type: Bool.Type) throws -> Bool {
        switch try decode(UInt32.self) {
        case 0: return false
        case 1: return true
        case let x: throw Error.boolOutOfRange(x)
        }
    }
    
    func decode(_ type: Float.Type) throws -> Float {
        var swapped = CFSwappedFloat32()
        try read(into: &swapped)
        return CFConvertFloatSwappedToHost(swapped)
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        var swapped = CFSwappedFloat64()
        try read(into: &swapped)
        return CFConvertDoubleSwappedToHost(swapped)
    }
    
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        switch type {
        case is Float.Type:
            return try decode(Float.self) as! T
            
        case is Double.Type:
            return try decode(Double.self) as! T
            
        case is Bool.Type:
            return try decode(Bool.self) as! T
            
        case let binaryT as XDRDecodable.Type:
            return try binaryT.init(fromBinary: self) as! T
            
        default:
            throw Error.typeNotConformingToXDRDecodable(type)
        }
    }
    
    /// Read the appropriate number of raw bytes directly into the given value. No byte
    /// swapping or other postprocessing is done.
    func read<T>(into: inout T) throws {
        try read(MemoryLayout<T>.size, into: &into)
    }
}

/// Internal methods for decoding raw data.
private extension XDRDecoder {
    /// Read the given number of bytes into the given pointer, advancing the cursor
    /// appropriately.
    func read(_ byteCount: Int, into: UnsafeMutableRawPointer) throws {
        if cursor + byteCount > data.count {
            throw Error.prematureEndOfData
        }
        
        data.withUnsafeBytes({
            let from = $0.baseAddress! + cursor
            memcpy(into, from, byteCount)
        })
        
        cursor += byteCount
    }
}

extension XDRDecoder: Decoder {
    public var codingPath: [CodingKey] { return [] }
    
    public var userInfo: [CodingUserInfoKey : Any] { return [:] }
    
    public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        return KeyedDecodingContainer(KeyedContainer<Key>(decoder: self))
    }
    
    public func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        return UnkeyedContainer(decoder: self)
    }
    
    public func singleValueContainer() throws -> SingleValueDecodingContainer {
        return UnkeyedContainer(decoder: self)
    }
    
    private struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
        var decoder: XDRDecoder
        
        var codingPath: [CodingKey] { return [] }
        
        var allKeys: [Key] { return [] }
        
        func contains(_ key: Key) -> Bool {
            return true
        }
        
        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
            return try decoder.decode(T.self)
        }
        
        func decodeNil(forKey key: Key) throws -> Bool {
            return true
        }
        
        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
            return try decoder.container(keyedBy: type)
        }
        
        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            return try decoder.unkeyedContainer()
        }
        
        func superDecoder() throws -> Decoder {
            return decoder
        }
        
        func superDecoder(forKey key: Key) throws -> Decoder {
            return decoder
        }
    }
    
    private struct UnkeyedContainer: UnkeyedDecodingContainer, SingleValueDecodingContainer {
        var decoder: XDRDecoder
        
        var codingPath: [CodingKey] { return [] }
        
        var count: Int? { return nil }
        
        var currentIndex: Int { return 0 }
        
        var isAtEnd: Bool { return false }
        
        func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
            return try decoder.decode(type)
        }
        
        func decodeNil() -> Bool {
            return true
        }
        
        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
            return try decoder.container(keyedBy: type)
        }
        
        func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            return self
        }
        
        func superDecoder() throws -> Decoder {
            return decoder
        }
    }
}

private extension FixedWidthInteger {
    static func from(xdrDecoder: XDRDecoder) throws -> Self {
        var v = Self.init()
        try xdrDecoder.read(into: &v)
        return self.init(bigEndian: v)
    }
}
