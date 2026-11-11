import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.phase {
            case .needsConfig:
                ContentUnavailableView {
                    Label("Falta configurar", systemImage: "wrench.and.screwdriver")
                } description: {
                    Text("Preencha o Config/Secrets.xcconfig com o ID do cliente Google e o ID da planilha, e instale o app de novo. O passo a passo está no README.")
                }
            case .signedOut:
                SignInView()
            case .loading:
                ProgressView("Lendo a planilha…")
                    .controlSize(.large)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Sem acesso à planilha", systemImage: "tablecells.badge.ellipsis")
                } description: {
                    Text(message)
                } actions: {
                    Button("Tentar de novo") { Task { await model.initialLoad() } }
                        .buttonStyle(.borderedProminent)
                }
            case .ready:
                TabView(selection: $model.tab) {
                    WorkoutView()
                        .tabItem { Label("Treino", systemImage: "dumbbell") }
                        .tag(AppModel.Tab.workout)
                    HistoryView()
                        .tabItem { Label("Histórico", systemImage: "calendar") }
                        .tag(AppModel.Tab.history)
                }
            }
        }
        .overlay(alignment: .top) {
            if let banner = model.banner {
                BannerView(banner: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { model.banner = nil }
            }
        }
        .animation(.smooth(duration: 0.25), value: model.banner)
    }
}

struct BannerView: View {
    let banner: Banner

    var body: some View {
        Label {
            Text(banner.text)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.leading)
        } icon: {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(banner.isError ? .red : .green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .accessibilityAddTraits(.isStaticText)
    }
}

struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var working = false
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Gimmy")
                    .font(.condensed(.largeTitle, weight: .bold))
                Text("Entre com a conta Google que tem acesso à planilha Controle de Treinos. Tudo continua sendo lido e gravado nela.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let error = model.signInError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button {
                working = true
                Task {
                    await model.signIn()
                    working = false
                }
            } label: {
                HStack(spacing: 8) {
                    if working { ProgressView().tint(.white) }
                    Text("Entrar com Google")
                        .font(.condensed(.title3, weight: .bold))
                }
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(working)
        }
        .padding(24)
    }
}
