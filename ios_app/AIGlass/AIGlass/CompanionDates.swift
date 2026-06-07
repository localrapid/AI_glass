//
//  CompanionDates.swift
//  AIGlass
//
//  Lightweight Japanese relative-date parsing so questions like 「昨日の」
//  「さっき」「3日前」 narrow the retrieval to a time window.
//

import Foundation

enum CompanionDates {
    /// A time window for the query, or nil if it has no date reference.
    static func range(from query: String, now: Date = Date(), calendar: Calendar = .current) -> ClosedRange<Date>? {
        let cal = calendar
        func startOfDay(_ d: Date) -> Date { cal.startOfDay(for: d) }
        func dayRange(_ offset: Int) -> ClosedRange<Date> {
            let start = startOfDay(cal.date(byAdding: .day, value: offset, to: now)!)
            let endExclusive = cal.date(byAdding: .day, value: 1, to: start)!
            return start...min(endExclusive.addingTimeInterval(-1), now)
        }

        if query.contains("今日") || query.contains("本日") { return dayRange(0) }
        if query.contains("昨日") || query.contains("きのう") { return dayRange(-1) }
        if query.contains("一昨日") || query.contains("おととい") { return dayRange(-2) }

        if query.contains("今朝") {
            let s = startOfDay(now)
            let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
            return s...min(noon, now)
        }
        if query.contains("さっき") || query.contains("先ほど") || query.contains("さきほど") {
            return now.addingTimeInterval(-3 * 3600)...now
        }
        if query.contains("今週") {
            let s = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfDay(now)
            return s...now
        }
        if query.contains("先週") {
            if let thisWeek = cal.dateInterval(of: .weekOfYear, for: now) {
                let lastStart = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start)!
                return lastStart...thisWeek.start.addingTimeInterval(-1)
            }
        }
        if let n = number(before: "日前", in: query) { return dayRange(-n) }
        if let n = number(before: "時間前", in: query) {
            let center = now.addingTimeInterval(-Double(n) * 3600)
            return center.addingTimeInterval(-1800)...center.addingTimeInterval(1800)
        }
        return nil
    }

    /// e.g. number(before: "日前") in "3日前" -> 3 (supports full-width digits).
    private static func number(before suffix: String, in s: String) -> Int? {
        let pattern = "([0-9０-９]+)" + NSRegularExpression.escapedPattern(for: suffix)
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: nsRange), let r = Range(m.range(at: 1), in: s) else { return nil }
        let digits = String(s[r]).applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? String(s[r])
        return Int(digits)
    }
}
