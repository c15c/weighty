import SwiftUI

/// Everyone's scale is moved by different things, so the tag list has to be
/// theirs. Renaming keeps history intact, because entries store identifiers.
struct TagSettingsView: View {
    @State private var tags: [TagDefinition] = TagCatalog.all
    @State private var newLabel = ""
    @State private var newSymbol = "tag"
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                ForEach($tags) { $tag in
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(TagCatalog.symbolChoices, id: \.self) { symbol in
                                Button {
                                    tag.symbol = symbol
                                    persist()
                                } label: {
                                    Label(symbol, systemImage: symbol)
                                }
                            }
                        } label: {
                            Image(systemName: tag.symbol)
                                .frame(width: 28, height: 28)
                                .background(Color(.tertiarySystemFill), in: Circle())
                        }

                        TextField("Tag name", text: $tag.label)
                            .onSubmit(persist)
                    }
                }
                .onDelete { offsets in
                    tags.remove(atOffsets: offsets)
                    persist()
                }
                .onMove { source, destination in
                    tags.move(fromOffsets: source, toOffset: destination)
                    persist()
                }
            } header: {
                Text("Your tags")
            } footer: {
                Text("Renaming a tag updates it everywhere, including past entries. Deleting one leaves earlier entries untouched.")
            }

            Section("Add a tag") {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(TagCatalog.symbolChoices, id: \.self) { symbol in
                            Button {
                                newSymbol = symbol
                            } label: {
                                Label(symbol, systemImage: symbol)
                            }
                        }
                    } label: {
                        Image(systemName: newSymbol)
                            .frame(width: 28, height: 28)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }

                    TextField("For example, long flight", text: $newLabel)
                        .onSubmit(add)
                }

                Button("Add tag", action: add)
                    .disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section {
                Button("Restore default tags", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("Tags")
        .toolbar { EditButton() }
        .onDisappear(perform: persist)
        .alert("Restore default tags?", isPresented: $confirmReset) {
            Button("Restore", role: .destructive) {
                TagCatalog.resetToDefaults()
                tags = TagCatalog.all
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your custom tags are removed from the list. Entries already tagged with them keep their tags.")
        }
    }

    private func add() {
        let label = newLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        let id = TagCatalog.makeIdentifier(for: label, existing: tags)
        tags.append(TagDefinition(id: id, label: label, symbol: newSymbol))
        newLabel = ""
        newSymbol = "tag"
        persist()
    }

    private func persist() {
        let cleaned = tags
            .map { TagDefinition(id: $0.id,
                                 label: $0.label.trimmingCharacters(in: .whitespaces),
                                 symbol: $0.symbol) }
            .filter { !$0.label.isEmpty }
        TagCatalog.save(cleaned)
    }
}
