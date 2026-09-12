# FB Report 2

**Title:** NavigationSplitView (regular width): changing the sidebar selection while the detail's NavigationStack has pushed content detaches the incoming detail root — `.task` cancelled and re-run on every such switch

**Area:** SwiftUI / Navigation

**Environment:**
- Xcode 27A266a, macOS 26A428
- Reproduced on iPad, landscape (regular width) — iOS 26 (latest) on hardware and the iOS 27.0 simulator (runtime 24.1.434.0)

## Description

In a `NavigationSplitView` on regular width (iPad, sidebar and detail visible side by side) with the documented composition — a `NavigationStack` embedded in the detail column — changing the sidebar selection **while the stack has pushed content** always detaches and re-inserts the incoming detail root:

```
init 5                 ← new detail root for the new selection
load START 5
onAppear 5
onDisappear 5          ← detached while visible
load START 5           ← .task re-fired
onAppear 5
load CANCELLED 5       ← first task cancelled
load DONE 5
deep onDisappear …     ← the OLD stack content pops only now, a beat later
```

The `.task` of the incoming root is cancelled and re-run — a real-world detail screen performs its (network) load twice on **every** selection change made while the previous detail was pushed deep. Selection changes made while the stack is at its root are clean (single `init`/`load`/`onAppear`).

The log ordering shows the cause: the pop-to-root of the old stack content and the root swap for the new selection are processed in **separate update beats** (the old pushed view's `onDisappear` arrives after the new root has already loaded). The detail root is re-hosted between the two.

**Workaround attempts that do NOT help:** binding the stack's path and clearing it synchronously in the same update as the selection write (custom selection setter performing `path.removeAll()`) — the churn is identical, so the app cannot avoid it by popping the stack itself.

This makes the documented "selection-driven split view + stack in detail" composition pay a duplicated load on a common iPad interaction (user drilled into detail content, then picks another item in the sidebar).

## Steps to Reproduce

1. Create an iPad app with the code below (single file).
2. Run on an iPad, landscape, so sidebar and detail are both visible.
3. Tap "Chat 1". After it loads, tap "Open detail page" (pushes onto the detail stack).
4. Now tap "Chat 2" in the sidebar.
5. Watch the console.

## Expected

The new detail root appears once: one `init`, one `load START`, one `onAppear`, one `load DONE`.

## Actual

`init → load START → onAppear → onDisappear → load START → onAppear → load CANCELLED → load DONE` — the incoming root is detached/re-inserted and its task runs twice. Reproduces on every selection change made while the stack is pushed; never when the stack is at root.

## Minimal Code

```swift
import SwiftUI
import Observation
import os

private let log = Logger(subsystem: "Repro", category: "split")

struct ChatItem: Hashable, Identifiable { let id: String }

@MainActor @Observable
final class ThreadModel {
    enum Phase { case loading, loaded }
    private(set) var phase: Phase = .loading
    let id: String
    init(id: String) { self.id = id; log.debug("init \(id)") }
    func load() async {
        log.debug("load START \(self.id)")
        do {
            try await Task.sleep(for: .milliseconds(400))   // stands in for a network fetch
            phase = .loaded
            log.debug("load DONE \(self.id)")
        } catch {
            log.error("load CANCELLED \(self.id)")
        }
    }
}

struct ThreadView: View {
    @State private var model: ThreadModel
    init(id: String) { _model = State(initialValue: ThreadModel(id: id)) }
    var body: some View {
        Group {
            switch model.phase {
                case .loading:
                    ProgressView()
                case .loaded:
                    VStack(spacing: 12) {
                        Text("Loaded \(model.id)")
                        NavigationLink("Open detail page", value: "page-\(model.id)")
                    }
            }
        }
        .task { await model.load() }
        .onAppear { log.debug("onAppear \(model.id)") }
        .onDisappear { log.debug("onDisappear \(model.id)") }
    }
}

struct ContentView: View {
    @State private var selection: ChatItem?
    private let chats = (1...8).map { ChatItem(id: "\($0)") }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(chats) { chat in
                    NavigationLink("Chat \(chat.id)", value: chat)
                }
            }
            .navigationTitle("Chats")
        } detail: {
            NavigationStack {
                detailRoot
                    .navigationDestination(for: String.self) { route in
                        VStack(spacing: 12) {
                            Text("Deep route: \(route)")
                            NavigationLink("Push deeper", value: route + "+")
                        }
                        .onAppear { log.debug("deep onAppear \(route)") }
                        .onDisappear { log.debug("deep onDisappear \(route)") }
                    }
            }
        }
    }

    @ViewBuilder private var detailRoot: some View {
        if let selection {
            ThreadView(id: selection.id).id(selection.id)
        } else {
            Text("Pick a chat")
        }
    }
}
```

## Notes

- Selection changes with the stack at root are clean; only switch-while-pushed churns — fully deterministic, reproduces every time.
- Binding the path (`NavigationStack(path:)`) and clearing it synchronously with the selection change does not prevent the detach.
- Companion report filed for the compact-width behavior of the same composition (detail-column NavigationStack breaking pushes on iPhone).
