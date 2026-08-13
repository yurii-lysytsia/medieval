import SwiftUI

struct SaveManagerView: View {
    @ObservedObject var game: GameStore
    let allowsSaving: Bool
    let onLoad: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var saveName = ""
    @State private var pendingDeletion: SaveMetadata?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Збережені партії").font(.title2.bold())
                Spacer()
                Button("Закрити") { dismiss() }
            }
            if allowsSaving {
                HStack {
                    TextField("Назва збереження", text: $saveName)
                    Button("Зберегти") {
                        if game.createManualSave(named: saveName) { saveName = "" }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            if let error = game.saveError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            if manualSaves.isEmpty {
                ContentUnavailableView("Збережень немає", systemImage: "archivebox", description: Text("Створіть перше збереження під час партії."))
            } else {
                List(manualSaves) { save in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(save.name).font(.headline)
                            Text("Хід \(save.turn) · \(save.playerNames.joined(separator: ", "))")
                            Text(save.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Завантажити") { onLoad(save.id) }
                        Button(role: .destructive) { pendingDeletion = save } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 430)
        .confirmationDialog(
            "Видалити «\(pendingDeletion?.name ?? "")»?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Видалити", role: .destructive) {
                if let pendingDeletion { game.deleteSave(pendingDeletion.id) }
                pendingDeletion = nil
            }
            Button("Скасувати", role: .cancel) { pendingDeletion = nil }
        }
    }

    private var manualSaves: [SaveMetadata] {
        game.saves.filter { $0.kind == .manual }
    }
}
