import SwiftUI

final class CodeInput: ObservableObject {
    @Published var text = ""
}

struct PairView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var discovery: Discovery
    @StateObject private var input = CodeInput()

    private var code: String {
        get { input.text }
        nonmutating set { input.text = newValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.awaitingCode {
                Text("Enter the 6-digit code shown on the board")
                TextField("123456", text: $input.text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onSubmit(submit)
                if model.codeRejected {
                    Text("Wrong code, try again").foregroundStyle(.red)
                }
                HStack {
                    Button("Cancel") { model.cancelPairing() }
                    Button("Pair", action: submit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(code.count != 6)
                }
            } else if model.status == .pairing {
                Text("Contacting board…")
                Button("Cancel") { model.cancelPairing() }
            } else if discovery.boards.isEmpty {
                Text("Searching for boards on the local network…")
            } else {
                Text("Choose a board")
                ForEach(discovery.boards) { board in
                    Button("\(board.name) (\(board.id))") {
                        code = ""
                        model.startPairing(board)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 320)
    }

    private func submit() {
        guard code.count == 6 else { return }
        model.submitPairCode(code)
    }
}
