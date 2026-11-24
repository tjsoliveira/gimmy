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
                    Text("Preencha o Config/Secrets.xcconfig com o ID do cliente Google e o ID da planilha, e gere o app de novo.")
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
                        .toolbarBackground(Color.appSurface, for: .tabBar)
                        .toolbarBackground(.visible, for: .tabBar)
                    HistoryView()
                        .tabItem { Label("Histórico", systemImage: "calendar") }
                        .tag(AppModel.Tab.history)
                        .toolbarBackground(Color.appSurface, for: .tabBar)
                        .toolbarBackground(.visible, for: .tabBar)
                    SetupView()
                        .tabItem { Label("Configurar", systemImage: "slider.horizontal.3") }
                        .tag(AppModel.Tab.setup)
                        .toolbarBackground(Color.appSurface, for: .tabBar)
                        .toolbarBackground(.visible, for: .tabBar)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .foregroundStyle(Color.textPrimary)
        .tint(.linearBlue)
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            if let banner = model.banner {
                BannerView(banner: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { model.banner = nil }
            }
        }
        .animation(.smooth(duration: 0.25), value: model.banner)
        .alert("Montar uma rotina nova?", isPresented: Binding(
            get: { model.newRoutineOffer != nil },
            set: { if !$0 { model.newRoutineOffer = nil } }
        ), presenting: model.newRoutineOffer) { offer in
            Button("Montar rotina nova") { Task { await model.acceptNewRoutine(offer) } }
            Button("Agora não", role: .cancel) {}
        } message: { offer in
            Text("Você mudou séries neste treino de \(offer.routine). A configuração atual encerra hoje e uma nova, igual a este treino, vale a partir de amanhã.")
        }
    }
}

struct BannerView: View {
    let banner: Banner

    var body: some View {
        Label {
            Text(banner.text)
                .font(AppFont.bodyBold)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.leading)
        } icon: {
            Image(systemName: banner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(banner.isError ? Color.statusDanger : Color.statusSuccess)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.appSurfaceHigh, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Color.appBorderStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
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
                    .font(AppFont.display)
                    .foregroundStyle(Color.textPrimary)
                Text("Entre com a conta Google que tem acesso à planilha Controle de Treinos. Tudo continua sendo lido e gravado nela.")
                    .font(AppFont.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if let error = model.signInError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.statusDanger)
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
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(working)
        }
        .padding(24)
    }
}
