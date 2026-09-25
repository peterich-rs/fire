import WidgetKit

struct FireWidgetEntry: TimelineEntry {
    let date: Date
    let data: FireWidgetData?

    static var placeholder: FireWidgetEntry {
        FireWidgetEntry(date: Date(), data: .placeholder)
    }

    static var snapshot: FireWidgetEntry {
        placeholder
    }
}

struct FireWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FireWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (FireWidgetEntry) -> Void) {
        completion(.snapshot)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FireWidgetEntry>) -> Void) {
        let entry = FireWidgetEntry(date: Date(), data: FireWidgetData.load())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}
