import Foundation
@testable import FujiCookbook

/// Bytes that pass the Kitchen's pre-upload checks, for every test that develops a file through
/// the mock camera. The mock never reads the bytes; the service does, and refuses a file without
/// the RAF magic before it is sent. The default model, `X-Q9`, is one the registry can't place, so
/// the header decides nothing about whose file it is and a test about the camera's own answer is
/// decided by the camera. Tests about the header itself name a real body.
///
/// Laid out as `RAFHeader` reads it (its doc comment gives the sources): magic, version, camera ID,
/// the model NUL-padded to 32 bytes, firmware, then filler.
enum RAFFixture {
    static func raf(model: String = "X-Q9", cameraID: String = "FF189504", firmware: String = "0132",
                    length: Int = 4096) -> Data {
        var data = RAFHeader.magic
        data.append(Data("0201".utf8))
        data.append(Data(cameraID.utf8))
        var name = Data(model.utf8)
        name.append(Data(repeating: 0, count: 32 - name.count))
        data.append(name)
        data.append(Data(firmware.utf8))
        data.append(Data(repeating: 0x46, count: length - data.count))
        return data
    }
}
