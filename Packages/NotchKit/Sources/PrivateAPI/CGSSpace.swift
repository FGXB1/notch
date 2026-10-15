import CoreFoundation

// Private window-server calls exported by CoreGraphics (SkyLight). A space with a high absolute level
// stays visible over full-screen apps and the lock screen. Signatures are reverse-engineered, so keep every use behind `CGSSpace`.

public typealias CGSConnectionID = Int32
public typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
public func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSSpaceCreate")
public func CGSSpaceCreate(_ connection: CGSConnectionID, _ flags: Int32, _ options: CFDictionary?) -> CGSSpaceID

@_silgen_name("CGSSpaceDestroy")
public func CGSSpaceDestroy(_ connection: CGSConnectionID, _ space: CGSSpaceID)

@_silgen_name("CGSSpaceSetAbsoluteLevel")
public func CGSSpaceSetAbsoluteLevel(_ connection: CGSConnectionID, _ space: CGSSpaceID, _ level: Int32)

@_silgen_name("CGSAddWindowsToSpaces")
public func CGSAddWindowsToSpaces(_ connection: CGSConnectionID, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
public func CGSRemoveWindowsFromSpaces(_ connection: CGSConnectionID, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSShowSpaces")
public func CGSShowSpaces(_ connection: CGSConnectionID, _ spaces: CFArray)

@_silgen_name("CGSHideSpaces")
public func CGSHideSpaces(_ connection: CGSConnectionID, _ spaces: CFArray)
