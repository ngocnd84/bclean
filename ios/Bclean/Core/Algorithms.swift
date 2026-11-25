import Foundation

/// Gom nhóm các phần tử có quan hệ "giống nhau" (bắc cầu).
struct UnionFind {
    private var parent: [Int]
    private var rank: [Int]

    init(_ n: Int) {
        parent = Array(0..<n)
        rank = Array(repeating: 0, count: n)
    }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var cur = x
        while parent[cur] != root {
            let next = parent[cur]
            parent[cur] = root
            cur = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let ra = find(a), rb = find(b)
        guard ra != rb else { return }
        if rank[ra] < rank[rb] {
            parent[ra] = rb
        } else if rank[ra] > rank[rb] {
            parent[rb] = ra
        } else {
            parent[rb] = ra
            rank[ra] += 1
        }
    }

    mutating func groups(minSize: Int) -> [[Int]] {
        var map: [Int: [Int]] = [:]
        for i in 0..<parent.count {
            map[find(i), default: []].append(i)
        }
        return map.values
            .filter { $0.count >= minSize }
            .map { $0.sorted() }
            .sorted { $0[0] < $1[0] }
    }
}

/// Tìm ảnh trùng bằng dHash 64-bit.
/// Kỹ thuật multi-index: chia hash thành 4 khúc 16 bit. Hai hash lệch ≤ 3 bit
/// chắc chắn trùng nhau ít nhất 1 khúc (nguyên lý Dirichlet) → chỉ so trong cùng khúc, không cần so N².
enum DuplicateFinder {
    static func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

    static func groups(hashes: [UInt64?],
                       aspects: [Double],
                       maxHamming: Int = 3,
                       maxBucket: Int = 800) -> [[Int]] {
        let maxH = min(maxHamming, 3)
        var uf = UnionFind(hashes.count)
        var buckets = [[UInt16: [Int]]](repeating: [:], count: 4)

        for (i, h) in hashes.enumerated() {
            guard let h else { continue }
            for c in 0..<4 {
                let key = UInt16(truncatingIfNeeded: h >> UInt64(c * 16))
                buckets[c][key, default: []].append(i)
            }
        }

        for c in 0..<4 {
            for (_, list) in buckets[c] where list.count > 1 && list.count <= maxBucket {
                for x in 0..<(list.count - 1) {
                    for y in (x + 1)..<list.count {
                        let i = list[x], j = list[y]
                        guard let hi = hashes[i], let hj = hashes[j] else { continue }
                        guard hamming(hi, hj) <= maxH else { continue }
                        let ai = aspects[i], aj = aspects[j]
                        guard abs(ai - aj) <= 0.05 * max(ai, aj) else { continue }
                        uf.union(i, j)
                    }
                }
            }
        }
        return uf.groups(minSize: 2)
    }
}

/// Tìm ảnh giống nhau: chỉ so các ảnh chụp gần nhau về thời gian (ảnh chụp liên tiếp).
/// `dates` phải được sắp xếp tăng dần.
enum SimilarFinder {
    static func groups(dates: [Date],
                       window: TimeInterval,
                       maxNeighbors: Int = 6,
                       onProgress: ((Int) -> Void)? = nil,
                       isSimilar: (Int, Int) -> Bool) -> [[Int]] {
        var uf = UnionFind(dates.count)
        for i in 0..<dates.count {
            var j = i + 1
            var checked = 0
            while j < dates.count, checked < maxNeighbors,
                  dates[j].timeIntervalSince(dates[i]) <= window {
                if isSimilar(i, j) { uf.union(i, j) }
                j += 1
                checked += 1
            }
            if i % 50 == 0 { onProgress?(i) }
        }
        return uf.groups(minSize: 2)
    }

    /// Chỉ những ảnh có "hàng xóm" trong cửa sổ thời gian mới cần tính feature print (tiết kiệm pin & thời gian)
    static func indicesNeedingFeatures(dates: [Date], window: TimeInterval) -> Set<Int> {
        var need = Set<Int>()
        guard dates.count > 1 else { return need }
        for i in 0..<(dates.count - 1) where dates[i + 1].timeIntervalSince(dates[i]) <= window {
            need.insert(i)
            need.insert(i + 1)
        }
        return need
    }
}

/// Hạn mức miễn phí theo ngày (reset 0h mỗi ngày theo giờ máy).
struct FreeQuota {
    let key: String
    let limit: Int
    private let defaults: UserDefaults
    private let now: () -> Date

    init(key: String, limit: Int, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.key = key
        self.limit = limit
        self.defaults = defaults
        self.now = now
    }

    static let deletes = FreeQuota(key: "quota_delete", limit: AppConfig.freeDeletesPerDay)
    static let compress = FreeQuota(key: "quota_compress", limit: AppConfig.freeCompressPerDay)

    private var today: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now())
    }

    var used: Int {
        defaults.string(forKey: key + "_day") == today ? defaults.integer(forKey: key + "_count") : 0
    }

    var remaining: Int { max(0, limit - used) }

    func canUse(_ n: Int) -> Bool { n <= remaining }

    func consume(_ n: Int) {
        let total = used + n
        defaults.set(today, forKey: key + "_day")
        defaults.set(total, forKey: key + "_count")
    }
}
