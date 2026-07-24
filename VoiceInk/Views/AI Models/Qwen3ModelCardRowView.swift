import SwiftUI
import AppKit
import Qwen3ASR

struct Qwen3ModelCardRowView: View {
    let model: Qwen3Model
    @ObservedObject var transcriptionModelManager: TranscriptionModelManager

    private var isCurrent: Bool {
        transcriptionModelManager.currentTranscriptionModel?.name == model.name
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                headerSection
                metadataSection
                descriptionSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionSection
        }
        .padding(16)
        .background(AppCardBackground(isSelected: isCurrent))
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))

            Text("Experimental")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.8)))
                .foregroundColor(.white)

            Spacer()
        }
    }

    private var metadataSection: some View {
        HStack(spacing: 12) {
            Label("Multilingual", systemImage: "globe")
            Label(model.size, systemImage: "internaldrive")
        }
        .font(.system(size: 11))
        .foregroundColor(Color(.secondaryLabelColor))
        .lineLimit(1)
    }

    private var descriptionSection: some View {
        Text(model.description)
            .font(.system(size: 11))
            .foregroundColor(Color(.secondaryLabelColor))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private var actionSection: some View {
        HStack(spacing: 8) {
            if isCurrent {
                Text("Default Model")
                    .font(.system(size: 12))
                    .foregroundColor(Color(.secondaryLabelColor))
            } else {
                Button(action: {
                    transcriptionModelManager.setDefaultTranscriptionModel(model)
                }) {
                    Text("Set as Default")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Menu {
                Button {
                    showInFinder()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20, height: 20)
        }
    }

    private func showInFinder() {
        // ponytail: both Qwen3 variants use HuggingFace cache now
        let url = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface", isDirectory: true)
        let target = FileManager.default.fileExists(atPath: url.path)
            ? url
            : url.deletingLastPathComponent()
        NSWorkspace.shared.open(target)
    }
}
