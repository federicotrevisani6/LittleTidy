import Darwin
import Foundation

/// Measures the APFS private size of a directory tree: the bytes not shared
/// with a clone or held by a local snapshot. Simulator test clones are created
/// with `clonefile`, and a Time Machine local snapshot keeps every block that
/// existed when it was taken, so allocated size can far exceed what removal
/// frees right away.
///
/// The result is a lower bound on immediately freed space. Blocks shared only
/// between items removed together are freed too, and snapshot-held blocks are
/// freed when macOS purges the snapshot; neither is counted here.
public struct APFSReclaimEstimator: Sendable {
    public init() {}

    /// Returns nil when the volume does not report private sizes (non-APFS),
    /// so callers fall back to allocated size instead of claiming zero.
    public func minimumReclaimableBytes(at root: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return nil
        }
        var total: Int64 = 0
        var measuredAny = false
        var sawRegularFile = false
        for case let url as URL in enumerator {
            if Task.isCancelled { return nil }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true else { continue }
            sawRegularFile = true
            // An unreadable file contributes nothing, which keeps the lower bound valid.
            if let size = privateSize(atPath: url.path) {
                total += size
                measuredAny = true
            }
        }
        if !sawRegularFile { return 0 }
        return measuredAny ? total : nil
    }

    private func privateSize(atPath path: String) -> Int64? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        request.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        var buffer = [UInt8](repeating: 0, count: 64)
        let status = getattrlist(path, &request, &buffer, buffer.count, UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW))
        guard status == 0 else { return nil }
        return buffer.withUnsafeBytes { raw in
            // Layout: u_int32_t length, attribute_set_t returned, off_t private size.
            let returned = raw.loadUnaligned(fromByteOffset: 4, as: attribute_set_t.self)
            guard returned.forkattr & attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) != 0 else { return nil }
            return Int64(raw.loadUnaligned(fromByteOffset: 4 + MemoryLayout<attribute_set_t>.size, as: off_t.self))
        }
    }
}
