//
//  DebugLog.swift
//  NetoSensei
//
//  Centralised debug logging that compiles out in Release.
//  Replaces direct print() calls so console output never ships to users.
//

import Foundation

/// Print to the console in Debug builds only. No-op in Release.
@inlinable
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
