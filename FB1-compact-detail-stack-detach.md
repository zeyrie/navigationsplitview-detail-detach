# FB24753146

**Title:** NavigationSplitView (compact): NavigationStack in the detail column causes the pushed detail view to be detached and re-inserted mid-push — `.task` is cancelled; with NavigationLink rows the view is never re-attached and hangs

**Area:** SwiftUI / Navigation

**Environment:**
- Xcode 27A266a, macOS 26A428
- Reproduced on a physical iPhone running **iOS 26 (latest)** and on the **iOS 27.0 simulator** (runtime 24.1.434.0, iPhone 17) — present on both major versions

## Description

In a `NavigationSplitView` on compact width (iPhone), wrapping the **detail column's root in a `NavigationStack`** — the pattern the `NavigationSplitView` documentation itself prescribes for same-column navigation ("You can also embed a NavigationStack in a column…") — makes the split view detach and re-insert the freshly pushed detail view during selection-driven navigation.

Observable symptoms on the pushed detail view (verified via `onAppear`/`onDisappear` logging and `os.Logger`):

1. The incoming detail receives `onAppear`, then `onDisappear`, **while it remains visible on screen**. Its `.task` is cancelled mid-flight.
2. What happens next depends on the sidebar row type:
   - Rows using `.tag(_:)` inside `List(selection:)`: the view re-attaches (`onAppear` fires again) and `.task` re-runs → every real-world load (network fetch) runs **twice**, the first cancelled.
   - Rows using `NavigationLink(value:)` (the documented idiom): the view **never re-attaches**. Its cancelled `.task` never re-runs, so a view that loads content in `.task` shows its loading state forever, while remaining fully visible. `@State` and view identity are preserved throughout (single model `init`) — only the attachment churns.
3. With a **non-nil initial selection** (e.g. the app launches with a default sidebar item selected), even the *first* push is affected, and the initial selection is not presented on compact at all. With a `nil` initial selection, the first push is clean and the problem starts from the second push (after navigating back).
4. A bare `.navigationDestination(for:)` attached to the detail root content (without an explicit `NavigationStack`) reproduces the same detach.

**Removing the `NavigationStack` from the detail column removes the problem completely** — the identical structure (same rows, same `@Observable` selection model, same detail content, same `.task`) is then clean across launch, repeated pushes, and sidebar data refreshes. This was isolated by a step-by-step bisect changing one variable per run.

The bug therefore makes the documented split-view + in-column-stack composition unusable on iPhone: any detail screen that starts asynchronous work in `.task` either duplicates that work on every entry or hangs permanently, depending on the sidebar row type.

## Steps to Reproduce

1. Create an iPhone app with the code below (single file).
2. Run on an iPhone (or iPhone simulator), portrait.
3. Tap "Chat 1" in the list. Navigate back. Tap "Chat 2".
4. Watch the console.

## Expected

Each detail push: one `init`, one `load START`, one `onAppear`, one `load DONE`. No `onDisappear` for a view that stays on screen; no cancelled task.

## Actual

Second push (first push too, if `selection` starts non-nil):

```
init 2
load START 2
onAppear 2
onDisappear 2        ← view is still on screen
load CANCELLED 2     ← .task cancelled
                     ← with NavigationLink rows: nothing further, spinner forever
```

With `.tag` rows instead of `NavigationLink`, the sequence continues `load START 2 / onAppear 2 / load DONE 2` — the work runs twice.

**Toggle:** delete the `NavigationStack { … }` wrapper (leave `detailRoot` bare) and every push is clean.

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
                case .loading: ProgressView()
                case .loaded: Text("Loaded \(model.id)")
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
            // DELETE this NavigationStack wrapper → every push is clean.
            // KEEP it → the second push (and later ones) detach the incoming
            // detail: onDisappear while visible, .task cancelled, never re-run.
            NavigationStack {
                detailRoot
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

- Reproduced on device and simulator.
- Independent of how the selection is stored (`@State` value vs `@Observable` class property) and of how the binding is created (`@Bindable` vs `@State` projection) — all combinations were tested; only the presence of the detail-column `NavigationStack` (or a `navigationDestination` on the detail root) flips the behavior.
- Likely related to the lifecycle double-execution regression discussed in forums thread 765401 (task/onAppear/onDisappear running twice, DTS-confirmed as a potential bug).
- Companion report for the regular-width behavior of the same composition: FB24753158.
