import Foundation

/// Side-by-side placement for overlapping events on a day timeline.
///
/// Events that overlap (directly or through a chain) form a cluster; each event gets the leftmost
/// free column in its cluster, and every event in the cluster shares the cluster's column count.
public enum TimelineLayout {
    public struct Slot: Equatable, Sendable {
        public let column: Int
        public let columnCount: Int

        public init(column: Int, columnCount: Int) {
            self.column = column
            self.columnCount = columnCount
        }
    }

    public static func slots<ID: Hashable>(for items: [(id: ID, start: Date, end: Date)]) -> [ID: Slot] {
        // Earliest first; on equal starts the longer event takes the leftmost column.
        let sorted = items.sorted { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }
        var result: [ID: Slot] = [:]

        var cluster: [(id: ID, column: Int)] = []
        var columnEnds: [Date] = []   // end time of the last event in each column
        var clusterEnd = Date.distantPast

        func closeCluster() {
            for entry in cluster {
                result[entry.id] = Slot(column: entry.column, columnCount: columnEnds.count)
            }
            cluster.removeAll()
            columnEnds.removeAll()
        }

        for item in sorted {
            if item.start >= clusterEnd { closeCluster() }
            if let free = columnEnds.firstIndex(where: { $0 <= item.start }) {
                columnEnds[free] = item.end
                cluster.append((item.id, free))
            } else {
                columnEnds.append(item.end)
                cluster.append((item.id, columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, item.end)
        }
        closeCluster()
        return result
    }
}
