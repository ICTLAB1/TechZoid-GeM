import SwiftUI

struct ItemEditorView: View {
    @State var item: VaultItem
    var isNew: Bool
    var onSaved: ((VaultItem) -> Void)? = nil

    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var showingAddField = false
    @State private var newFieldLabel = ""
    @State private var generatorTarget: UUID?

    init(item: VaultItem, isNew: Bool) {
        _item = State(initialValue: item)
        self.isNew = isNew
        _hasReminder = State(initialValue: item.reminderDate != nil)
        _reminderDate = State(initialValue: item.reminderDate ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name this entry", text: $item.title)
                        .font(.headline)
                    TextField("Short description (optional)", text: $item.subtitle)
                } header: {
                    HStack(spacing: 10) {
                        CategoryBadge(category: item.category, size: 26)
                        Text(item.category.singular)
                    }
                }

                Section {
                    HolderField(holder: $item.holder, suggestions: holderSuggestions)
                } header: {
                    Text("Belongs to")
                } footer: {
                    Text(store.familyMembers.isEmpty
                         ? "Whose account or policy this is. Add family members in Settings to pick from a list instead of typing a name each time."
                         : "Whose account or policy this is. Used to filter each list — handy once everyone has entries in here.")
                }

                Section("Details") {
                    ForEach($item.fields) { $field in
                        EditableFieldRow(
                            field: $field,
                            onGenerate: field.kind.isSecret ? { generatorTarget = field.id } : nil
                        )
                    }
                    .onDelete { offsets in
                        item.fields.remove(atOffsets: offsets)
                    }

                    Button {
                        showingAddField = true
                    } label: {
                        Label("Add another field", systemImage: "plus.circle")
                    }
                }

                Section {
                    Toggle("Remind me", isOn: $hasReminder.animation())
                    if hasReminder {
                        DatePicker(dueLabel, selection: $reminderDate, displayedComponents: .date)

                        Picker("Repeats", selection: $item.reminderRepeat) {
                            ForEach(ReminderRepeat.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }

                        Picker("Tell me", selection: $item.reminderLeadDays) {
                            Text("On the day").tag(0)
                            Text("1 day before").tag(1)
                            Text("3 days before").tag(3)
                            Text("1 week before").tag(7)
                            Text("2 weeks before").tag(14)
                            Text("1 month before").tag(30)
                        }
                    }
                } header: {
                    Text(item.category.reminderLabel)
                } footer: {
                    if hasReminder {
                        Text(reminderExplanation)
                    } else if item.category == .loan || item.category == .insurance || item.category == .card {
                        Text("Set this and Vault will tell you before every payment, by name — which bank, whose account, and how much.")
                    }
                }

                Section("Notes") {
                    TextEditor(text: $item.notes)
                        .frame(minHeight: 100)
                }

                Section {
                    TagEditor(tags: $item.tags, suggestions: store.allTags)
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Free-form labels that cut across categories — “tax saving”, “Dad”, “review in April”.")
                }

                Section {
                    Toggle("Pin to home screen", isOn: $item.isFavourite)
                }

                if isNew {
                    Section {
                        Label("Save, and you'll land here ready to scan or attach documents.", systemImage: "doc.viewfinder")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text("Documents are added from the entry's own screen, after saving.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                if isNew, item.holder.isEmpty { item.holder = settings.lastHolder }
            }
            .navigationTitle(isNew ? "New \(item.category.singular)" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                }
            }
            .alert("Add a field", isPresented: $showingAddField) {
                TextField("Field name", text: $newFieldLabel)
                Button("Add") { addField(kind: .text) }
                Button("Add as secret") { addField(kind: .secret) }
                Button("Cancel", role: .cancel) { newFieldLabel = "" }
            } message: {
                Text("A secret field stays hidden until you tap to reveal it.")
            }
            .sheet(item: Binding(
                get: { generatorTarget.map { IdentifiedUUID(id: $0) } },
                set: { generatorTarget = $0?.id }
            )) { target in
                PasswordGeneratorSheet { generated in
                    if let index = item.fields.firstIndex(where: { $0.id == target.id }) {
                        item.fields[index].value = generated
                    }
                }
            }
        }
    }

    /// Named family members first, so the picker steers toward the real
    /// roster; any older free-typed names still in use tag along so nothing
    /// already in the vault stops being offered.
    private var holderSuggestions: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for name in store.familyMembers.map(\.name) + store.holders {
            let key = name.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            ordered.append(name)
        }
        return ordered
    }

    /// "Next EMI date" reads oddly once it repeats; "First EMI date" doesn't.
    private var dueLabel: String {
        guard item.reminderRepeat != .never else { return item.category.reminderLabel }
        switch item.category {
        case .loan: return "First EMI date"
        case .card: return "First due date"
        case .insurance: return "Next renewal date"
        default: return item.category.reminderLabel
        }
    }

    /// Spells the rule back in a sentence, so nobody has to infer it from two
    /// pickers sitting next to each other.
    private var reminderExplanation: String {
        let lead: String
        switch item.reminderLeadDays {
        case 0: lead = "on the day"
        case 1: lead = "1 day before"
        case let days: lead = "\(days) days before"
        }

        let date = reminderDate.formatted(date: .abbreviated, time: .omitted)
        switch item.reminderRepeat {
        case .never:
            return "One reminder, \(lead) \(date)."
        case .monthly:
            let day = Calendar.current.component(.day, from: reminderDate)
            return "A reminder \(lead) the \(ordinal(day)) of every month, starting \(date)."
        case .quarterly, .halfYearly, .yearly:
            return "A reminder \(lead) each due date, \(item.reminderRepeat.label.lowercased()) from \(date)."
        }
    }

    private func ordinal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func addField(kind: FieldKind) {
        let label = newFieldLabel.trimmingCharacters(in: .whitespaces)
        newFieldLabel = ""
        guard !label.isEmpty else { return }
        item.fields.append(ItemField(label: label, kind: kind))
    }

    private func save() {
        var toSave = item
        toSave.reminderDate = hasReminder ? reminderDate : nil
        toSave.title = toSave.title.trimmingCharacters(in: .whitespacesAndNewlines)
        toSave.subtitle = toSave.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        toSave.holder = toSave.holder.trimmingCharacters(in: .whitespacesAndNewlines)
        toSave.tags = toSave.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // A blank subtitle is filled in from the field that best identifies it.
        if toSave.subtitle.isEmpty {
            let key = CategoryTemplates.subtitleField(for: toSave.category)
            if let match = toSave.fields.first(where: { $0.label == key && !$0.isEmpty }), match.kind != .secret {
                toSave.subtitle = match.value
            }
        }

        // Drop template fields the user never filled in, but keep any they
        // added themselves so the labels aren't lost.
        toSave.fields = toSave.fields.filter { !$0.isEmpty }

        if toSave.title.isEmpty, let first = toSave.fields.first(where: { $0.kind != .secret && !$0.isEmpty }) {
            toSave.title = first.value
        }

        if !toSave.holder.isEmpty { settings.lastHolder = toSave.holder }

        store.save(toSave)
        onSaved?(toSave)
        dismiss()
    }
}

/// Wrapper so a plain UUID can drive a `.sheet(item:)`.
struct IdentifiedUUID: Identifiable {
    var id: UUID
}

struct HolderField: View {
    @Binding var holder: String
    var suggestions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("e.g. Abhinav, Priya, or Joint", text: $holder)

            let options = Array(Set(suggestions + ["Joint"])).sorted()
            if !options.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(options, id: \.self) { option in
                            Button {
                                holder = option
                            } label: {
                                Text(option)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(holder == option ? Theme.accent.opacity(0.18) : Color(.tertiarySystemFill))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

struct EditableFieldRow: View {
    @Binding var field: ItemField
    var onGenerate: (() -> Void)?

    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if field.kind.isSecret {
                    if let onGenerate {
                        Button(action: onGenerate) {
                            Image(systemName: "die.face.5")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("Generate a strong value")
                    }
                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            switch field.kind {
            case .secret:
                if isRevealed {
                    TextField(field.label, text: $field.value)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField(field.label, text: $field.value)
                        .textContentType(.oneTimeCode)   // stops the keychain from offering to save it
                }
            case .multiline:
                TextEditor(text: $field.value)
                    .frame(minHeight: 70)
            case .number, .money:
                TextField(field.label, text: $field.value)
                    .keyboardType(.decimalPad)
            case .phone:
                TextField(field.label, text: $field.value)
                    .keyboardType(.phonePad)
            case .email:
                TextField(field.label, text: $field.value)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            case .url:
                TextField(field.label, text: $field.value)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            case .text, .date:
                TextField(field.label, text: $field.value)
            }
        }
        .padding(.vertical, 2)
    }
}

struct PasswordGeneratorSheet: View {
    var onUse: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var options = PasswordGenerator.Options()
    @State private var generated = PasswordGenerator.make()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(generated)
                        .font(.system(.title3, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    Button {
                        generated = PasswordGenerator.make(options)
                    } label: {
                        Label("Generate another", systemImage: "arrow.clockwise")
                    }
                }

                Section("Shape") {
                    Stepper("Length: \(options.length)", value: $options.length, in: 8...64)
                    Toggle("Capitals", isOn: $options.includeUppercase)
                    Toggle("Digits", isOn: $options.includeDigits)
                    Toggle("Symbols", isOn: $options.includeSymbols)
                    Toggle("Avoid look-alike characters", isOn: $options.avoidAmbiguous)
                }

                Section {
                    Button {
                        onUse(generated)
                        dismiss()
                    } label: {
                        Text("Use this password").fontWeight(.semibold)
                    }
                } footer: {
                    Text("Generated from the system's cryptographic random source, on this iPhone.")
                }
            }
            .navigationTitle("Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: options) { _, updated in
                generated = PasswordGenerator.make(updated)
            }
        }
    }
}
