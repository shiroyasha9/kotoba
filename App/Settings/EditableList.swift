import SwiftUI

/// A list the owner edits inside a grouped form's section, as in System Settings > Login Items: a native list (a form
/// row cannot be selected or dragged, a list row can) as tall as its rows measure, so it never scrolls inside the form,
/// with Add (a menu, or a button with `add`) and Remove under it. Remove, the context menu and the Delete key remove the
/// selected rows; with `edit`, a double click and the context menu's "Edit…" edit one. With no rows, `emptyText` shows
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

    @State private var selection: Set<Row.ID> = []
    /// The rows as tall as the system draws them; the list takes this height.
    @State private var height: CGFloat = 0

    init(
        rows: [Row], emptyText: String, addTitle: String, addHelp: String, isAddDisabled: Bool = false,
        removeTitle: String, remove: @escaping @MainActor (Set<Row.ID>) -> Void,
        move: (@MainActor (IndexSet, Int) -> Void)? = nil, add: (@MainActor () -> Void)? = nil,
        edit: (@MainActor (Row.ID) -> Void)? = nil,
        @ViewBuilder row: @escaping (Row) -> RowView, @ViewBuilder addItems: @escaping () -> AddItems,
        @ViewBuilder accessory: @escaping () -> Accessory
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
    }

    var body: some View {
        if rows.isEmpty {
            Text(emptyText).foregroundStyle(.secondary)
        } else {
            list
        }
        buttons
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

extension EditableList where AddItems == EmptyView {
    /// Add is a plain button: `add` opens what adds a row (Dictionary's sheet).
    init(
        rows: [Row], emptyText: String, addTitle: String, addHelp: String, removeTitle: String,
        remove: @escaping @MainActor (Set<Row.ID>) -> Void, add: @escaping @MainActor () -> Void,
        edit: (@MainActor (Row.ID) -> Void)? = nil, @ViewBuilder row: @escaping (Row) -> RowView,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.init(
            rows: rows, emptyText: emptyText, addTitle: addTitle, addHelp: addHelp, removeTitle: removeTitle,
            remove: remove, add: add, edit: edit, row: row, addItems: { EmptyView() }, accessory: accessory)
    }
}
