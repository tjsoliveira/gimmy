# Gimmy — instruções para o Claude

App de iPhone (SwiftUI) para registrar treinos. A planilha Google "Controle de Treinos" é a base de dados (abas Registro, Rotinas, Exercícios), lida e gravada pela API do Sheets. Veja o DESIGN.md para o visual. É um app pessoal: o README, em inglês, não tem (e não deve ter) instruções de instalação. Os IDs (Bundle ID, cliente Google, planilha) ficam em `Config/Secrets.xcconfig`, fora do git (modelo em `Config/Secrets.example.xcconfig`), e nos secrets do GitHub usados pelo CI.

## Regras

- **Testes contra regressão são obrigatórios.** Toda mudança em funcionalidade essencial vem com testes unitários em `GimmyTests/` (XCTest), novos ou atualizados. Essencial = leitura da planilha (`Parse`, `DayKey`, `RestInput`), regras de treino (`Ledger`: numeração com drop/rest-pause, 1RM, status, recordes, volume kg/lb, montagem do treino, sessões e estatísticas), rascunhos e rest-pause (`Drafts.swift`), treinos configurados e vigência (`Plan.swift`: séries planejadas, versões por data, cópia do treino) foco da tela de treino (`Focus.swift`), reordenação de séries (`SeriesOrder.swift`) e rotina nova a partir do treino (`NewRoutine.swift`).
- Mantenha a lógica testável fora das views e do `AppModel` (que fala com a rede): funções puras no `Model/`, chamadas pelo `AppModel`.
- O CI (`.github/workflows/build.yml`) roda os testes antes de gerar o IPA; o IPA só sai se eles passarem. Não há compilador Swift no ambiente de nuvem: confira o resultado no GitHub Actions depois do push.
- **Changelog:** todo commit acrescenta uma linha no `CHANGELOG.md`, no mesmo commit: `python3 .github/scripts/changelog.py "what changed"` (põe a linha sob a data do dia, no fuso de São Paulo). Escreva em inglês, dizendo o que mudou para quem usa o app, em uma frase. Vale para qualquer commit, inclusive só de documentação ou de CI; o workflow de prints já faz o mesmo nos commits dele.
- Não adicione funcionalidades que não foram pedidas.
- Visual: siga o DESIGN.md (Kinetic Dark Minimal) e os tokens de `Gimmy/App/Theme.swift`.
- A planilha não muda de formato sem combinar antes: o app usa as colunas que já existem, mais J (Tipos), K (Início) e L (Fim) na aba Rotinas. As colunas D e E da Rotinas são fórmulas e nunca são gravadas. A Unidade (D) da aba Exercícios aceita kg, lb ou placas; no volume em kg, cada placa vale 4,5 kg (estimativa), no app e nas fórmulas da planilha.
