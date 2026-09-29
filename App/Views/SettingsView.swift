import BoloKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    var body: some View {
        @Bindable var audio = app.audio
        NavigationStack {
            Form {
                Section {
                    Picker("Voice", selection: $audio.preferred) {
                        ForEach(AudioService.Source.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                    statusRow(title: "Recorded (AI)", ok: audio.recordedAvailable,
                              detail: audio.recordedAvailable
                                ? "\(audio.recordedClipCount) clips, two voices\(audio.recordedModel.map { " · \($0)" } ?? "")"
                                : "No recorded clips in this build.")
                    statusRow(title: "iPhone voice", ok: audio.systemAvailable,
                              detail: audio.systemVoiceDescription
                                ?? "No Gujarati voice installed. If your iPhone offers one, download it in Settings › Accessibility › Read & Speak › Voices.")

                    Toggle("Slower playback", isOn: $audio.slow)
                        .tint(Palette.madder)
                        .listRowBackground(Palette.indigo.opacity(0.6))

                    Button {
                        audio.play(AudioRequest(text: "કેમ છો?", voice: "male"))
                    } label: {
                        Label("Hear a sample", systemImage: "play.circle")
                    }
                    .disabled(!audio.canPlay)
                    .listRowBackground(Palette.indigo.opacity(0.6))
                } header: {
                    header("Voice")
                } footer: {
                    Text("Switch between the two to compare them. Lines play even with the silent switch on.")
                }

                Section {
                    Button("Reset all progress", role: .destructive) { confirmingReset = true }
                        .listRowBackground(Palette.indigo.opacity(0.6))
                } header: {
                    header("Progress")
                } footer: {
                    Text("\(app.startedCount) of \(app.content.phrases.count) phrases started · \(app.state.xp) XP · best run \(app.state.bestRun)")
                }

                Section {
                    aboutRow("Romanization is the working surface. The Gujarati script rides along and is never tested.")
                    aboutRow("The phrases have not yet been checked by a native speaker; register varies by region and familiarity.")
                    aboutRow("Type: Eczar and Hind Vadodara, SIL Open Font License 1.1.")
                } header: {
                    header("About")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ClothBackground())
            .font(Typeface.hind(16))
            .foregroundStyle(Palette.cream)
            .tint(Palette.gold)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset all progress?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { app.resetProgress() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every phrase goes back to unseen, and XP, streak and best run return to zero.")
            }
            .onAppear { audio.refreshSystemVoice() }
        }
        .presentationBackground(Palette.night)
    }

    private func header(_ text: String) -> some View {
        TrackedLabel(text: text, size: 11.5, tracking: 0.2, color: Palette.madder)
    }

    private func statusRow(title: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Palette.green : Palette.dim)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typeface.hind(16, .medium))
                Text(detail).font(Typeface.hind(13.5)).foregroundStyle(Palette.dim)
            }
        }
        .listRowBackground(Palette.indigo.opacity(0.6))
    }

    private func aboutRow(_ text: String) -> some View {
        Text(text)
            .font(Typeface.hind(14))
            .foregroundStyle(Palette.dim)
            .listRowBackground(Palette.indigo.opacity(0.6))
    }
}
