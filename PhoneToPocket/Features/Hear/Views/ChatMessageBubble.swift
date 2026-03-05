import SwiftUI

struct ChatMessageBubble: View {
    let message: ChatMessage
    var isStreaming: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser { Spacer(minLength: 60) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(message.isUser ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.isUser
                            ? Color.blue
                            : Color(.systemGray5),
                        in: RoundedRectangle(cornerRadius: 16)
                    )

                if isStreaming {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("思考中")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let desc = message.imageDescription, !desc.isEmpty {
                    HStack(spacing: 4) {
                        if message.isUser {
                            Image(systemName: "eye.fill")
                                .font(.caption2)
                            Text(desc)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            Text(desc)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Image(systemName: "eye.fill")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                }
            }

            if !message.isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }
}
