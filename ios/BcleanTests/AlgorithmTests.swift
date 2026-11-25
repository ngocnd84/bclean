import XCTest
@testable import Bclean

final class AlgorithmTests: XCTestCase {
    func testDuplicateFinderGroupsNearIdenticalHashes() {
        let a: UInt64 = 0xF0F0_F0F0_1234_5678
        let b: UInt64 = a ^ 0b101          // lệch 2 bit → trùng
        let c: UInt64 = 0x0F0F_0F0F_ABCD_EF01 // khác hẳn
        let groups = DuplicateFinder.groups(hashes: [a, b, c, nil], aspects: [1.33, 1.33, 1.33, 1.33])
        XCTAssertEqual(groups, [[0, 1]])
    }

    func testDuplicateFinderRespectsAspectRatio() {
        let a: UInt64 = 0xAAAA_BBBB_CCCC_DDDD
        let groups = DuplicateFinder.groups(hashes: [a, a], aspects: [0.75, 1.33])
        XCTAssertTrue(groups.isEmpty, "Ảnh dọc và ngang không được coi là trùng")
    }

    func testDuplicateFinderTransitive() {
        let a: UInt64 = 0x1111_2222_3333_4444
        let groups = DuplicateFinder.groups(hashes: [a, a ^ 1, a ^ 3], aspects: [1, 1, 1])
        XCTAssertEqual(groups, [[0, 1, 2]])
    }

    func testSimilarFinderOnlyComparesWithinWindow() {
        let t0 = Date(timeIntervalSince1970: 0)
        let dates = [t0, t0.addingTimeInterval(5), t0.addingTimeInterval(500), t0.addingTimeInterval(505)]
        var compared: [(Int, Int)] = []
        let groups = SimilarFinder.groups(dates: dates, window: 60) { a, b in
            compared.append((a, b))
            return true
        }
        XCTAssertEqual(groups, [[0, 1], [2, 3]])
        XCTAssertFalse(compared.contains { $0 == (1, 2) })
    }

    func testIndicesNeedingFeatures() {
        let t0 = Date(timeIntervalSince1970: 0)
        let dates = [t0, t0.addingTimeInterval(10), t0.addingTimeInterval(1000)]
        XCTAssertEqual(SimilarFinder.indicesNeedingFeatures(dates: dates, window: 60), [0, 1])
    }

    func testFreeQuotaResetsDaily() {
        let defaults = UserDefaults(suiteName: "bclean-tests")!
        defaults.removePersistentDomain(forName: "bclean-tests")
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let quota = FreeQuota(key: "q", limit: 30, defaults: defaults, now: { now })

        XCTAssertEqual(quota.remaining, 30)
        quota.consume(25)
        XCTAssertEqual(quota.remaining, 5)
        XCTAssertFalse(quota.canUse(6))
        XCTAssertTrue(quota.canUse(5))

        now = now.addingTimeInterval(86_400 * 1.5)
        XCTAssertEqual(quota.remaining, 30, "Sang ngày mới phải reset")
    }
}
