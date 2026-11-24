import CCoreKitRoutes

#if canImport(MachO)
    import MachO
#endif

/// What `@GET`, `@POST`, ... store in the binary's `corekit_routes` section: a function that writes its handler's
/// `RouteRegistration` into an uninitialized slot.
///
/// Reading the section finds every route without a central list, the way Swift Testing finds `@Test` functions.
public typealias RouteRecord = @convention(c) (UnsafeMutableRawPointer) -> Void

/// A handler and the router it's attached to.
public struct RouteRegistration: Sendable {
    let router: APIRouter
    let endpoint: Endpoint

    public init(router: APIRouter, endpoint: Endpoint) {
        self.router = router
        self.endpoint = endpoint
    }

    /// Called by the generated `RouteRecord`s.
    public static func write(_ registration: RouteRegistration, to slot: UnsafeMutableRawPointer) {
        slot.initializeMemory(as: RouteRegistration.self, to: registration)
    }

    /// Every route in the process, in section order.
    static func all() -> [RouteRegistration] {
        recordBuffers().flatMap { records in
            records.map { record in
                withUnsafeTemporaryAllocation(of: RouteRegistration.self, capacity: 1) { buffer in
                    let slot = buffer.baseAddress!
                    record(UnsafeMutableRawPointer(slot))
                    return slot.move()
                }
            }
        }
    }

    private static func recordBuffers() -> [UnsafeBufferPointer<RouteRecord>] {
        #if canImport(MachO)
            (0..<_dyld_image_count()).compactMap { index in
                var size: UInt = 0
                guard let header = _dyld_get_image_header(index),
                    let start = getsectiondata(
                        UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self), "__DATA_CONST", "__corekit_routes", &size)
                else { return nil }
                return records(from: UnsafeRawPointer(start), byteCount: Int(size))
            }
        #else
            guard let start = corekit_routes_start(), let end = corekit_routes_end() else { return [] }
            return [records(from: start, byteCount: end - start)]
        #endif
    }

    private static func records(from start: UnsafeRawPointer, byteCount: Int) -> UnsafeBufferPointer<RouteRecord> {
        UnsafeBufferPointer(start: start.assumingMemoryBound(to: RouteRecord.self), count: byteCount / MemoryLayout<RouteRecord>.stride)
    }
}
