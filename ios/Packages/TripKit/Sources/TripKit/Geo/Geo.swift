import Foundation

/// A WGS84 point. TripKit stays free of CoreLocation so it builds and tests anywhere.
public struct Coordinate: Codable, Sendable, Hashable {
    public var lat: Double
    public var lng: Double

    public init(_ lat: Double, _ lng: Double) {
        self.lat = lat
        self.lng = lng
    }
}

public enum Geo {
    public static let earthRadiusKm = 6371.0088

    @inline(__always) static func rad(_ d: Double) -> Double { d * .pi / 180 }
    @inline(__always) static func deg(_ r: Double) -> Double { r * 180 / .pi }

    /// Great-circle distance in km (same formula as scripts/geo-tools.mjs).
    public static func km(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = rad(b.lat - a.lat)
        let dLng = rad(b.lng - a.lng)
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(rad(a.lat)) * cos(rad(b.lat)) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * earthRadiusKm * asin(min(1, h.squareRoot()))
    }

    /// Initial bearing from a to b, degrees clockwise from true north, 0..<360.
    public static func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
        let φ1 = rad(a.lat), φ2 = rad(b.lat), Δλ = rad(b.lng - a.lng)
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let θ = deg(atan2(y, x))
        return (θ + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Signed difference b − a folded into −180…180.
    public static func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    public static func compass(_ bearing: Double) -> String {
        let dirs = ["Bắc", "Đông Bắc", "Đông", "Đông Nam", "Nam", "Tây Nam", "Tây", "Tây Bắc"]
        return dirs[Int((bearing / 45).rounded()) % 8]
    }

    /// Where a point projects onto a polyline: the distance along it and how far off it lies.
    public struct Projection: Sendable {
        public let kmAlong: Double
        public let offKm: Double
        public let point: Coordinate
        /// bearing of the segment the point projects onto
        public let heading: Double
    }

    /// Nearest point of a polyline, on a local flat projection (fine at walking and rail scales).
    public static func project(_ p: Coordinate, on line: [Coordinate]) -> Projection? {
        guard line.count > 1 else {
            guard let only = line.first else { return nil }
            return Projection(kmAlong: 0, offKm: km(p, only), point: only, heading: 0)
        }
        let kx = 111.32 * cos(rad(p.lat))
        let ky = 110.57
        var best: Projection?
        var acc = 0.0
        for i in 1 ..< line.count {
            let a = line[i - 1], b = line[i]
            let ax = (a.lng - p.lng) * kx, ay = (a.lat - p.lat) * ky
            let bx = (b.lng - p.lng) * kx, by = (b.lat - p.lat) * ky
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / len2)) : 0
            let qx = ax + dx * t, qy = ay + dy * t
            let off = (qx * qx + qy * qy).squareRoot()
            let seg = km(a, b)
            if best == nil || off < best!.offKm {
                let q = Coordinate(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t)
                best = Projection(kmAlong: acc + seg * t, offKm: off, point: q, heading: bearing(a, b))
            }
            acc += seg
        }
        return best
    }

    /// Length of a polyline in km.
    public static func length(_ line: [Coordinate]) -> Double {
        zip(line, line.dropFirst()).reduce(0) { $0 + km($1.0, $1.1) }
    }

    /// The point a given distance along a polyline.
    public static func point(along line: [Coordinate], km target: Double) -> Coordinate? {
        guard var prev = line.first else { return nil }
        var acc = 0.0
        for p in line.dropFirst() {
            let seg = km(prev, p)
            if acc + seg >= target, seg > 0 {
                let t = (target - acc) / seg
                return Coordinate(prev.lat + (p.lat - prev.lat) * t, prev.lng + (p.lng - prev.lng) * t)
            }
            acc += seg
            prev = p
        }
        return line.last
    }

    /// Bounding box as (south-west, north-east).
    public static func bounds(_ pts: [Coordinate]) -> (sw: Coordinate, ne: Coordinate)? {
        guard let f = pts.first else { return nil }
        var s = f.lat, w = f.lng, n = f.lat, e = f.lng
        for p in pts {
            s = min(s, p.lat)
            n = max(n, p.lat)
            w = min(w, p.lng)
            e = max(e, p.lng)
        }
        return (Coordinate(s, w), Coordinate(n, e))
    }
}

/// Google's encoded polyline algorithm at 1e-5, as written by the site's scripts.
public enum Polyline {
    public static func decode(_ str: String) -> [Coordinate] {
        var out: [Coordinate] = []
        let bytes = Array(str.utf8)
        var i = 0, lat = 0, lng = 0
        func next() -> Int? {
            var result = 0, shift = 0
            while i < bytes.count {
                let b = Int(bytes[i]) - 63
                i += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }
        while i < bytes.count {
            guard let dLat = next(), let dLng = next() else { break }
            lat += dLat
            lng += dLng
            out.append(Coordinate(Double(lat) / 1e5, Double(lng) / 1e5))
        }
        return out
    }

    public static func encode(_ pts: [Coordinate]) -> String {
        var out = ""
        var pLat = 0, pLng = 0
        func put(_ v: Int) {
            var v = v < 0 ? ~(v << 1) : (v << 1)
            while v >= 0x20 {
                out.unicodeScalars.append(UnicodeScalar(UInt8((0x20 | (v & 0x1F)) + 63)))
                v >>= 5
            }
            out.unicodeScalars.append(UnicodeScalar(UInt8(v + 63)))
        }
        for p in pts {
            let lat = Int((p.lat * 1e5).rounded()), lng = Int((p.lng * 1e5).rounded())
            put(lat - pLat)
            put(lng - pLng)
            pLat = lat
            pLng = lng
        }
        return out
    }
}
