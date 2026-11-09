// Connection.swift
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// SPDX-License-Identifier: GPL-2.0-only
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of the GNU General Public License version 2 as published by
// the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program; if not, see <https://www.gnu.org/licenses/>.

import Foundation

/// Where Ollama runs: on this Mac, or on another computer reached through an SSH tunnel.
/// The tunnel is /usr/bin/ssh forwarding a free local port to 127.0.0.1:11434 on the other
/// computer; it uses the user's SSH key and never asks for a password.
actor Connection {
    static let shared = Connection()
    static let ollamaPort = 11434

    /// Process id of the running tunnel, for the synchronous cleanup at quit.
    nonisolated(unsafe) static var tunnelPID: pid_t = 0

    private var process: Process?
    private var host: String?
    private var port = 0

    /// Last SSH error, shown in the status line and in Settings.
    private(set) var lastError: String?

    /// The SSH destination in use, or nil when Ollama runs on this Mac.
    nonisolated static var remoteHost: String? {
        let d = UserDefaults.standard
        guard d.bool(forKey: "useSSH") else { return nil }
        let h = (d.string(forKey: "sshHost") ?? "").trimmingCharacters(in: .whitespaces)
        return h.isEmpty ? nil : h
    }

    /// Base address of the Ollama API, opening or reopening the tunnel when needed.
    func base() async throws -> URL {
        guard let wanted = Connection.remoteHost else {
            stop()
            return AppInfo.ollamaBase
        }
        if let p = process, p.isRunning, host == wanted { return URL(string: "http://127.0.0.1:\(port)")! }
        stop()
        return try await open(wanted)
    }

    private func open(_ destination: String) async throws -> URL {
        let local = Self.freePort()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = [
            "-N", "-T", "-L", "127.0.0.1:\(local):127.0.0.1:\(Self.ollamaPort)",
            "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes", "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3", "-o", "StrictHostKeyChecking=accept-new",
            destination,
        ]
        let errors = Pipe()
        p.standardError = errors
        p.standardOutput = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            lastError = tr("No se pudo ejecutar ssh: ", "Could not run ssh: ") + error.localizedDescription
            throw OllamaError.remote(lastError!)
        }

        // Ready when the local end of the tunnel accepts connections.
        let until = Date().addingTimeInterval(20)
        while Date() < until {
            if !p.isRunning {
                let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let last = text.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces)
                lastError = tr("SSH a \(destination) falló: ", "SSH to \(destination) failed: ")
                    + (last ?? tr("código \(p.terminationStatus)", "exit code \(p.terminationStatus)"))
                throw OllamaError.remote(lastError!)
            }
            if await Self.accepts(local) {
                process = p; host = destination; port = local; lastError = nil
                Self.tunnelPID = p.processIdentifier
                UserDefaults.standard.set(Int(p.processIdentifier), forKey: "sshTunnelPID")
                return URL(string: "http://127.0.0.1:\(local)")!
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        p.terminate()
        lastError = tr("SSH a \(destination) no respondió en 20 s.", "SSH to \(destination) did not answer within 20 s.")
        throw OllamaError.remote(lastError!)
    }

    /// Closes the tunnel, if any.
    func stop() {
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        host = nil
        Self.tunnelPID = 0
        UserDefaults.standard.removeObject(forKey: "sshTunnelPID")
    }

    /// Ends the tunnel at quit, and one left behind by a previous run that did not quit cleanly.
    nonisolated static func cleanUp() {
        if tunnelPID > 0 { kill(tunnelPID, SIGTERM); tunnelPID = 0 }
        let old = pid_t(UserDefaults.standard.integer(forKey: "sshTunnelPID"))
        if old > 0, processName(old) == "ssh" { kill(old, SIGTERM) }
        UserDefaults.standard.removeObject(forKey: "sshTunnelPID")
    }

    private nonisolated static func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        return proc_name(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
    }

    private static func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    private static func accepts(_ port: Int) async -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        let len = socklen_t(MemoryLayout<sockaddr_in>.size)
        return withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) } } == 0
    }
}

/// Exits after closing the SSH tunnel (test and screenshot modes end with this, not with Quit).
func finish(_ code: Int32) -> Never {
    Connection.cleanUp()
    exit(code)
}
