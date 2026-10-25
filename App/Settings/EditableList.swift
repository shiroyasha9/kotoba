import SwiftUI

/// A list the owner edits inside a grouped form's section, as in System Settings > Login Items: a native list (a form
/// row cannot be selected or dragged, a list row can) as tall as its rows measure, so it never scrolls inside the form,
/// with Add (a menu, or a button with `add`) and Remove under it, or no buttons when the page's Add is in the window
/// toolbar (Dictionary). Remove, the context menu and the Delete key remove the selected rows; with `edit`, a double click and the context menu's "Edit…" edit one. With no rows, `emptyText` shows
/// in place of the list. The Microphone, Cleanup and Dictionary pages use it.
struct EditableList<Row: Identifiable, RowView: View, AddItems: View, Accessory: View>: View {
    let rows: [Row]
    let emptyText: String
    /// "Add to Order", "Add App": the Add button's accessible name.
    let addTitle: String
    let addHelp: String
    let isAddDisabled: Bool
    /// "Remove from Order", "Remove from List": the Remove button and the context menu item.
    let removeTitle: String
    let remove: @MainActor (Set<Row.ID>) -> Void
    /// Rows the owner can drag to order; nil for a list without an order.
    let move: (@MainActor (IndexSet, Int) -> Void)?
    /// Add as a plain button (a sheet follows); nil: Add is a menu of `addItems`.
    let add: (@MainActor () -> Void)?
    /// Edits one row: a double click, or "Edit…" in the context menu; nil: rows are not edited.
    let edit: (@MainActor (Row.ID) -> Void)?
    let row: (Row) -> RowView
    let addItems: () -> AddItems
    /// After the buttons, at the trailing edge.
    let accessory: () -> Accessory
    /// False: no Add and Remove under the list.
    private let showsButtons: Bool

    @State private var selection: Set<Row.ID> = []
    /// The rows as tall as the system draws them; the list takes this height.
    @State private var height: CGFloat = 0

    init(
        rows: [Row], emptyText: String, addTitle: String, addHelp: String, isAddDisabled: Bool = false,
        removeTitle: String, remove: @escaping @MainActor (Set<Row.ID>) -> Void,
        move: (@MainActor (IndexSet, Int) -> Void)? = nil, add: (@MainActor () -> Void)? = nil,
        edit: (@MainActor (Row.ID) -> Void)? = nil,
        @ViewBuilder row: @escaping (Row) -> RowView, @ViewBuilder addItems: @escaping () -> AddItems,
        @ViewBuilder accessory: @escaping () -> Accessory, showsButtons: Bool = true
    ) {
        self.rows = rows
        self.emptyText = emptyText
        self.addTitle = addTitle
        self.addHelp = addHelp
        self.isAddDisabled = isAddDisabled
        self.removeTitle = removeTitle
        self.remove = remove
        self.move = move
        self.add = add
        self.edit = edit
        self.row = row
        self.addItems = addItems
        self.accessory = accessory
        self.showsButtons = showsButtons
    }

    var body: some View {
        if rows.isEmpty {
            Text(emptyText).foregroundStyle(.secondary)
        } else {
            // The form's lines above and under the list in the text column, as every row line in a card (qa1-review
            // 7). A list alone in a row is drawn over the row's inset to the card's edges, and the form then draws the
            // lines edge to edge whatever guides the list gives; a stack keeps its guides, and the list in it takes the
            // row's inset back, so it still fills the row (measured: rows and lines where they were, 2026-10-25).
            VStack {
                list
                    .padding(-PageMetrics.formRowInset)
                    .ignoresSafeArea()
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in PageMetrics.formRowInset }
            .alignmentGuide(.listRowSeparatorTrailing) { $0.width - PageMetrics.formRowInset }
        }
        if showsButtons {
            buttons
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(rows) { item in
                row(item)
            }
            .onMove(perform: move)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Every row at least as tall as a row with a pop-up button (32 pt, Modes, measured offscreen 2026-10-16), so a
        // list of names (Microphone) is not denser than the other lists and form rows in the window.
        .environment(\.defaultMinListRowHeight, 32)
        .scrollDisabled(true)
        .onScrollGeometryChange(for: CGFloat.self, of: \.contentSize.height) { _, height in self.height = height }
        .frame(height: height)
        .contextMenu(forSelectionType: Row.ID.self) { ids in
            if let edit, ids.count == 1, let id = ids.first {
                Button("Edit…") { edit(id) }
            }
            Button(removeTitle, role: .destructive) { removeRows(ids) }
        } primaryAction: { ids in
            if let edit, ids.count == 1, let id = ids.first {
                edit(id)
            }
        }
        .onDeleteCommand { removeRows(selection) }
        // A row added or removed elsewhere (a sheet, a menu) can move the rows under the selection.
        .onChange(of: Set(rows.map(\.id))) { selection = [] }
    }

    private var buttons: some View {
        HStack {
            Group {
                if let add {
                    Button(addTitle, systemImage: "plus", action: add)
                } else {
                    Menu {
                        addItems()
                    } label: {
                        Label(addTitle, systemImage: "plus")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .disabled(isAddDisabled)
            .help(addHelp)
            Button(removeTitle, systemImage: "minus") { removeRows(selection) }
                .disabled(selection.isEmpty)
            Spacer()
            accessory()
        }
        // Icon-only buttons give the form no text to start the line above at.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .menuStyle(.borderlessButton)
    }

    private func removeRows(_ ids: Set<Row.ID>) {
        guard !ids.isEmpty else { return }
        remove(ids)
        selection = []
    }
}

extension EditableList where Accessory == EmptyView {
    init(
        rows: [Row], emptyText: String, addTitle: String, addHelp: String, isAddDisabled: Bool = false,
        removeTitle: String, remove: @escaping @MainActor (Set<Row.ID>) -> Void,
        move: (@MainActor (IndexSet, Int) -> Void)? = nil,
        @ViewBuilder row: @escaping (Row) -> RowView, @ViewBuilder addItems: @escaping () -> AddItems
    ) {
        self.init(
            rows: rows, emptyText: emptyText, addTitle: addTitle, addHelp: addHelp, isAddDisabled: isAddDisabled,
            removeTitle: removeTitle, remove: remove, move: move, row: row, addItems: addItems,
            accessory: { EmptyView() })
    }
}

extension EditableList where AddItems == EmptyView, Accessory == EmptyView {
    /// No buttons under the list: the page's Add is in the window toolbar, and the Delete key and the context menu
    /// remove rows, as in Passwords (Dictionary; owner QA 1, Q12).
    init(
        rows: [Row], emptyText: String, removeTitle: String, remove: @escaping @MainActor (Set<Row.ID>) -> Void,
        edit: @escaping @MainActor (Row.ID) -> Void, @ViewBuilder row: @escaping (Row) -> RowView
    ) {
        self.init(
            rows: rows, emptyText: emptyText, addTitle: "", addHelp: "", removeTitle: removeTitle, remove: remove,
            edit: edit, row: row, addItems: { EmptyView() }, accessory: { EmptyView() }, showsButtons: false)
    }
}
