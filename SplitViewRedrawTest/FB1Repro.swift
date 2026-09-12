//
//  FB1Repro.swift
//
//  FB1 — NavigationSplitView (compact): a NavigationStack in the detail column causes
//  the pushed detail view to be detached and re-inserted mid-push. The `.task` is
//  cancelled; with NavigationLink rows the view is never re-attached and hangs.
//
//  Run on iPhone. Tap "Chat 1" → back → "Chat 2". Watch the console:
//
//      init 2 / load START 2 / onAppear 2 / onDisappear 2 / load CANCELLED 2
//      (nothing further — the spinner stays forever)
//
//  TOGGLE: delete the NavigationStack wrapper in `detail:` below (leave `detailRoot`
//  bare) and every push is clean: init / load START / onAppear / load DONE.
//
//  Also reproduces with: a bare .navigationDestination on the detail root instead of
//  the stack; and on the FIRST push when `selection` starts non-nil. With `.tag` rows
//  instead of NavigationLink, the view re-attaches and the task runs twice instead of
//  hanging.
//

import SwiftUI
import Observation
import os

private let log = Logger(subsystem: "Repro", category: "fb1")

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
                case .loading: ProgressView()
                case .loaded: Text("Loaded \(model.id)")
            }
        }
        .task { await model.load() }
        .onAppear { log.debug("onAppear \(model.id, privacy: .public)") }
        .onDisappear { log.debug("onDisappear \(model.id, privacy: .public)") }
    }
}

struct FB1ReproView: View {
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

#Preview {
    FB1ReproView()
}
