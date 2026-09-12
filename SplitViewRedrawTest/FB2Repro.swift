//
//  FB2Repro.swift
//
//  FB24753158 — NavigationSplitView (regular width): changing the sidebar selection while the
//  detail's NavigationStack has pushed content detaches the incoming detail root.
//  Its `.task` is cancelled and re-run — the load runs twice on every such switch.
//
//  Run on iPad, landscape (sidebar + detail visible). Tap "Chat 1" → after it loads,
//  tap "Open detail page" (pushes onto the detail stack) → now tap "Chat 2" in the
//  sidebar. Watch the console:
//
//      init 2 / load START 2 / onAppear 2 / onDisappear 2
//      load START 2 / onAppear 2 / load CANCELLED 2 / load DONE 2
//      deep onDisappear …      ← the old pushed page pops only now, a beat later
//
//  Selection changes made while the stack is at its root are clean. Binding the path
//  and clearing it synchronously in the same update as the selection write does NOT
//  prevent the detach.
//

import SwiftUI
import Observation
import os

private let log = Logger(subsystem: "Repro", category: "fb2")

private struct ChatItem: Hashable, Identifiable { let id: String }

@MainActor @Observable
private final class ThreadModel {
    enum Phase { case loading, loaded }
    private(set) var phase: Phase = .loading
    let id: String
    init(id: String) { self.id = id; log.debug("init \(id, privacy: .public)") }
    func load() async {
        log.debug("load START \(self.id, privacy: .public)")
        do {
            try await Task.sleep(for: .milliseconds(400))   // stands in for a network fetch
            phase = .loaded
            log.debug("load DONE \(self.id, privacy: .public)")
        } catch {
            log.error("load CANCELLED \(self.id, privacy: .public)")
        }
    }
}

private struct ThreadView: View {
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
        .onAppear { log.debug("onAppear \(model.id, privacy: .public)") }
        .onDisappear { log.debug("onDisappear \(model.id, privacy: .public)") }
    }
}

struct FB2ReproView: View {
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
                        .onAppear { log.debug("deep onAppear \(route, privacy: .public)") }
                        .onDisappear { log.debug("deep onDisappear \(route, privacy: .public)") }
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

#Preview {
    FB2ReproView()
}
