
import Foundation
import Compression
import zlib

func log(_ s: String) { FileHandle.standardError.write(("[bridge] " + s + "\n").data(using: .utf8)!) }

func gunzip(_ data: Data) -> Data? {
   var stream = z_stream()
   var status = inflateInit2_(&stream, 47 , ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
   guard status == Z_OK else { return nil }
   defer { inflateEnd(&stream) }
   var out = Data()
   let chunkSize = 1 << 18
   var chunk = [UInt8](repeating: 0, count: chunkSize)
   var input = [UInt8](data)
   input.withUnsafeMutableBufferPointer { inBuf in
      stream.next_in = inBuf.baseAddress
      stream.avail_in = uInt(inBuf.count)
      repeat {
         var produced = 0
         chunk.withUnsafeMutableBufferPointer { buf in
            stream.next_out = buf.baseAddress
            stream.avail_out = uInt(chunkSize)
            status = inflate(&stream, Z_NO_FLUSH)
            produced = chunkSize - Int(stream.avail_out)
         }
         if produced > 0 { out.append(contentsOf: chunk[0..<produced]) }
      } while status == Z_OK && stream.avail_in > 0
   }
   if status == Z_STREAM_END || !out.isEmpty { return out }
   return nil
}

func readLE32(_ d: Data, _ off: Int) -> Int { Int(Int32(littleEndian: d.subdata(in: off..<off+4).withUnsafeBytes { $0.load(as: Int32.self) })) }
func cstr(_ d: Data, _ off: Int, _ len: Int) -> String {
   var bytes = [UInt8](d.subdata(in: off..<off+len))
   if let z = bytes.firstIndex(of: 0) { bytes = Array(bytes[..<z]) }
   return String(decoding: bytes, as: UTF8.self)
}

struct ReplayInfo {
   var engine = ""
   var game = ""
   var map = ""
   var gameTime = 0
   var players: [[String: Any]] = []
   var winners: [Int] = []
}

func parseStartScript(_ script: String, into info: inout ReplayInfo) {
   var teamAlly: [Int: Int] = [:]
   var sectionStack: [String] = []
   var current: [String: String] = [:]
   func flush() {
      guard let sec = sectionStack.last?.lowercased() else { return }
      if sec == "game" {
         if let m = current["mapname"] { info.map = m }
         if let g = current["gametype"] { info.game = g }
      } else if sec.hasPrefix("team") , let idx = Int(sec.dropFirst(4)) {
         if let a = current["allyteam"], let ai = Int(a) { teamAlly[idx] = ai }
      }
   }
   var pending: [(section: String, kv: [String: String])] = []
   for rawLine in script.replacingOccurrences(of: "\r", with: "").split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("[") && line.hasSuffix("]") {
         sectionStack.append(String(line.dropFirst().dropLast()))
         current = [:]
      } else if line == "}" {
         flush()
         pending.append((sectionStack.last ?? "", current))
         sectionStack.removeLast()
         current = [:]
      } else if let eq = line.firstIndex(of: "=") , line.hasSuffix(";") {
         let k = String(line[..<eq]).trimmingCharacters(in: .whitespaces).lowercased()
         let v = String(line[line.index(after: eq)...].dropLast()).trimmingCharacters(in: .whitespaces)
         current[k] = v
      }
   }
   for (sec, kv) in pending {
      let s = sec.lowercased()
      if s.hasPrefix("player") {
         if kv["spectator"] == "1" { continue }
         var p: [String: Any] = ["name": kv["name"] ?? "?"]
         if let t = kv["team"], let ti = Int(t) { p["allyTeamId"] = teamAlly[ti] ?? 0 }
         else { p["allyTeamId"] = 0 }
         if let cc = kv["countrycode"] { p["countryCode"] = cc }
         if let r = kv["rank"], let ri = Int(r) { p["rank"] = ri }
         if let sk = kv["skill"] { p["skill"] = sk }
         info.players.append(p)
      } else if s.hasPrefix("ai") && !s.hasPrefix("aioverride") {
         var p: [String: Any] = ["name": kv["name"] ?? (kv["shortname"] ?? "AI")]
         p["aiId"] = kv["shortname"] ?? "ai"
         if let t = kv["team"], let ti = Int(t) { p["allyTeamId"] = teamAlly[ti] ?? 0 }
         else { p["allyTeamId"] = 0 }
         info.players.append(p)
      }
   }
}

func readReplay(_ absPath: String) -> ReplayInfo? {
   guard let raw = FileManager.default.contents(atPath: absPath), let d = gunzip(raw) else { return nil }
   guard d.count > 348, cstr(d, 0, 16) == "spring demofile" else { return nil }
   var info = ReplayInfo()
   let headerSize = readLE32(d, 20)
   info.engine = cstr(d, 24, 256)
   let scriptSize = readLE32(d, 304)
   info.gameTime = readLE32(d, 312)
   let winnersSize = readLE32(d, headerSize - 4)
   if headerSize + scriptSize <= d.count, scriptSize > 0,
      let script = String(data: d.subdata(in: headerSize..<headerSize+scriptSize), encoding: .utf8) {
      parseStartScript(script, into: &info)
   }
   if winnersSize > 0 && winnersSize <= 32 && d.count >= winnersSize {
      info.winners = d.suffix(winnersSize).map { Int($0) }
   }
   return info
}

let args = CommandLine.arguments
func argValue(_ name: String) -> String? {
   if let i = args.firstIndex(of: name), i + 1 < args.count { return args[i + 1] }
   return nil
}
guard let writeDir = argValue("--write-dir") else { log("usage: wrapper-bridge --write-dir <path> [--pr-downloader <path>]"); exit(1) }
let prDownloader = argValue("--pr-downloader")

let listenFD = socket(AF_INET, SOCK_STREAM, 0)
var yes: Int32 = 1
setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
var addr = sockaddr_in()
addr.sin_family = sa_family_t(AF_INET)
addr.sin_addr.s_addr = inet_addr("127.0.0.1")
addr.sin_port = 0
withUnsafePointer(to: &addr) { p in
   p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
      _ = bind(listenFD, sp, socklen_t(MemoryLayout<sockaddr_in>.size))
   }
}
var len = socklen_t(MemoryLayout<sockaddr_in>.size)
withUnsafeMutablePointer(to: &addr) { p in
   p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
      _ = getsockname(listenFD, sp, &len)
   }
}
let port = Int(UInt16(bigEndian: addr.sin_port))
listen(listenFD, 4)

let connInfo: [String: Any] = ["_sl_address": "127.0.0.1", "_sl_port": port, "_sl_write_path": writeDir]
let connJSON = try! JSONSerialization.data(withJSONObject: connInfo)
try? connJSON.write(to: URL(fileURLWithPath: writeDir + "/sl-connection.json"))
log("listening on 127.0.0.1:\(port), write-dir \(writeDir)")

func sendMsg(_ fd: Int32, _ name: String, _ command: [String: Any]) {
   let obj: [String: Any] = ["name": name, "command": command]
   guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
   data.append(0x0A)
   data.withUnsafeBytes { _ = write(fd, $0.baseAddress, data.count) }
}

func handleDownload(_ fd: Int32, _ cmd: [String: Any]) {
   let name = cmd["name"] as? String ?? ""
   let type = (cmd["type"] as? String ?? "").lowercased()
   if type == "resource", let res = cmd["resource"] as? [String: Any],
      let urlStr = res["url"] as? String, let url = URL(string: urlStr) {
      let destRel = res["destination"] as? String ?? name
      let extract = (res["extract"] as? Bool) ?? false
      let destPath = writeDir + "/" + destRel
      DispatchQueue.global().async {
         let sem = DispatchSemaphore(value: 0)
         var ok = false
         let task = URLSession.shared.downloadTask(with: url) { tmp, resp, err in
            defer { sem.signal() }
            guard let tmp = tmp, err == nil,
                  (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return }
            let fm = FileManager.default
            do {
               if extract {
                  try fm.createDirectory(atPath: destPath, withIntermediateDirectories: true)
                  let unzip = Process()
                  unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                  unzip.arguments = ["-x", "-k", tmp.path, destPath]
                  try unzip.run(); unzip.waitUntilExit()
                  ok = unzip.terminationStatus == 0
               } else {
                  try fm.createDirectory(atPath: (destPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                  try? fm.removeItem(atPath: destPath)
                  try fm.moveItem(atPath: tmp.path, toPath: destPath)
                  ok = true
               }
            } catch { log("resource save failed: \(error)") }
         }
         task.resume()
         sem.wait()
         sendMsg(fd, "DownloadFinished", ["name": destRel, "isSuccess": ok, "isAborted": false])
      }
      return
   }
   if let prd = prDownloader, type == "map" || type == "game" {
      DispatchQueue.global().async {
         let p = Process()
         p.executableURL = URL(fileURLWithPath: prd)
         p.arguments = ["--filesystem-writepath", writeDir,
                        type == "map" ? "--download-map" : "--download-game", name]
         var ok = false
         do { try p.run(); p.waitUntilExit(); ok = p.terminationStatus == 0 }
         catch { log("pr-downloader failed: \(error)") }
         sendMsg(fd, "DownloadFinished", ["name": name, "isSuccess": ok, "isAborted": false])
      }
      return
   }
   sendMsg(fd, "DownloadFinished", ["name": name, "isSuccess": false, "isAborted": false])
}

// The lobby only asks for folders inside the write dir: the dir itself, demos/,
// LuaUI/Widgets. Anything else is refused rather than handed to /usr/bin/open,
// which would launch whatever the path points at.
func openInFinder(_ raw: String) {
   let path = raw.hasPrefix("file://") ? (URL(string: raw)?.path ?? "") : raw
   guard !path.isEmpty else { return }
   let target = URL(fileURLWithPath: path).standardized.path
   let root = URL(fileURLWithPath: writeDir).standardized.path
   guard target == root || target.hasPrefix(root + "/") else {
      log("refusing to open \(target), outside the write dir")
      return
   }
   // a folder the user has not filled yet does not exist, and open would fail on it
   try? FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
   let proc = Process()
   proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
   proc.arguments = [target]
   do { try proc.run() } catch { log("open \(target) failed: \(error)") }
}

func handleLine(_ fd: Int32, _ line: Data) {
   guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
         let name = obj["name"] as? String else { return }
   let cmd = obj["command"] as? [String: Any] ?? [:]
   switch name {
   case "ReadReplayInfo":
      guard let rel = cmd["relativePath"] as? String else { return }
      DispatchQueue.global().async {
         if let info = readReplay(writeDir + "/" + rel) {
            sendMsg(fd, "ReplayInfo", [
               "relativePath": rel,
               "engine": info.engine,
               "game": info.game,
               "map": info.map,
               "players": info.players,
               "gameTime": info.gameTime,
               "winningAllyTeamIds": info.winners,
            ])
         } else {
            log("failed to read replay \(rel)")
         }
      }
   case "Download":
      handleDownload(fd, cmd)
   case "OpenFile":
      guard let path = cmd["path"] as? String else { return }
      openInFinder(path)
   default:
      break
   }
}

signal(SIGPIPE, SIG_IGN)
let parentPID = getppid()
DispatchQueue.global().async {
   while getppid() == parentPID { sleep(2) }
   try? FileManager.default.removeItem(atPath: writeDir + "/sl-connection.json")
   exit(0)
}

while true {
   let fd = accept(listenFD, nil, nil)
   if fd < 0 { continue }
   log("lobby connected")
   DispatchQueue.global().async {
      var buf = Data()
      var chunk = [UInt8](repeating: 0, count: 65536)
      while true {
         let n = read(fd, &chunk, chunk.count)
         if n <= 0 { break }
         buf.append(contentsOf: chunk[0..<n])
         while let nl = buf.firstIndex(of: 0x0A) {
            let line = buf.subdata(in: buf.startIndex..<nl)
            buf.removeSubrange(buf.startIndex...nl)
            if !line.isEmpty { handleLine(fd, line) }
         }
      }
      close(fd)
      log("lobby disconnected")
   }
}
