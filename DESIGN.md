# DESIGN.md — Kinetic Dark Minimal

Design system do Gimmy: alta densidade, modo escuro, inspirado no Linear e em ferramentas de precisão.
Os tokens abaixo estão implementados em `Gimmy/App/Theme.swift`.

```yaml
name: Kinetic Dark Minimal
description: A high-density, dark-mode design system tailored for gym tracking and workout analytics, inspired by Linear and high-precision developer tools.
version: 1.0.0

theme:
  color_mode: DARK
  font: Inter
  roundness: ROUND_EIGHT
  accent_color: "#5E6AD2"

colors:
  # Base surfaces & Elevation
  surface: "#131315"
  surface-dim: "#0E0E10"
  surface-bright: "#39393B"
  surface-container-lowest: "#0E0E10"
  surface-container-low: "#1C1B1E"
  surface-container: "#222126"
  surface-container-high: "#262529"
  surface-container-highest: "#323135"

  # Borders & Dividers
  border-subtle: "rgba(255, 255, 255, 0.06)"
  border-default: "rgba(255, 255, 255, 0.10)"
  border-strong: "rgba(255, 255, 255, 0.16)"

  # Text & Content Hierarchy
  text-primary: "#F4F4F5"
  text-secondary: "#A1A1AA"
  text-muted: "#71717A"
  text-inverse: "#0E0E10"

  # Brand & Primary Actions (Linear Electric Indigo)
  primary: "#5E6AD2"
  primary-hover: "#4E5AC0"
  primary-container: "rgba(94, 106, 210, 0.15)"
  on-primary: "#FFFFFF"

  # Semantic Workout Set Types
  set-warmup: "#F59E0B"     # Âmbar / Aquecimento
  set-normal: "#71717A"     # Cinza Neutro / Série padrão
  set-dropset: "#A855F7"    # Roxo Elétrico / Drop-set
  set-restpause: "#14B8A6"  # Verde-azulado / Rest-pause (adicionado no app; não estava no design original)
  set-failure: "#EF4444"    # Vermelho Coral / Falha muscular

  # Status & Indicators
  status-success: "#22C55E" # Verde / Concluído e Streaks
  status-warning: "#F59E0B" # Âmbar
  status-danger: "#EF4444"  # Vermelho

radii:
  none: "0px"
  xs: "4px"
  sm: "6px"       # Badges pequenos, atalhos de incremento (chips)
  md: "8px"       # Botões secundários, inputs, pílulas
  lg: "12px"      # Botões de ação principais, cards internos
  card: "16px"    # Cards principais de exercício e modais
  full: "9999px"  # Pílulas, tags de status e avatares

spacing:
  2xs: "4px"
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "20px"
  xl: "24px"
  2xl: "32px"
  3xl: "48px"

typography:
  font_family: "Inter, -apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif"
  numeric_font_family: "'SF Pro Rounded', Inter, sans-serif"

  scales:
    display:      { size: "28px", weight: "700", line_height: "1.2",  tracking: "-0.02em" }
    title_large:  { size: "20px", weight: "700", line_height: "1.3",  tracking: "-0.01em" }
    title_medium: { size: "17px", weight: "600", line_height: "1.35", tracking: "-0.01em" }
    body:         { size: "15px", weight: "400", line_height: "1.4" }
    body_bold:    { size: "15px", weight: "600", line_height: "1.4" }
    caption:      { size: "12px", weight: "500", line_height: "1.3" }
    caption_bold: { size: "10px", weight: "700", line_height: "1.2", tracking: "0.05em", text_transform: "uppercase" }

components:
  card:
    background: "surface"
    border: "border-subtle"
    radius: "card"
    padding: "md"

  primary_button:
    background: "primary"
    text: "on-primary"
    radius: "lg"
    height: "48px"
    font_weight: "600"
    shadow: "0 4px 14px rgba(94, 106, 210, 0.3)"

  secondary_button:
    background: "surface-container-high"
    text: "text-primary"
    border: "border-default"
    radius: "md"
    height: "36px"

  set_badge:
    width: "34px"
    height: "34px"
    radius: "full"
    border_width: "1.5px"
    font_weight: "700"
```

## Notas de implementação

- **Fonte:** o app usa SF Pro (fonte do sistema) no lugar da Inter, como nos componentes de referência; números em SF Pro Rounded.
- **Tela de treino:** foco no exercício atual. O exercício com séries pendentes fica aberto; tocar numa série abre o painel de edição (Entrada Rápida + opções da série); os demais aparecem como cards compactos (círculo vazio para os que não começaram, meio círculo para os em andamento, check para os concluídos). Tocar num card compacto abre o exercício; os exercícios podem ser feitos em qualquer ordem. Quando todas as séries do treino estão registradas, todos os exercícios ficam fechados com o check, inclusive o último. O exercício aberto tem um botão com seta para cima, no canto do título, que o recolhe: aí todos ficam fechados até você tocar em um.
- **Reordenar séries:** segurar uma série e arrastar sobre outra põe a arrastada no lugar dela; as demais mantêm a ordem. A série vai junto com os drops ou mini-séries dela (só a série principal pode ser arrastada), e o alvo fica destacado em índigo. Segurar sem arrastar continua abrindo o menu da série. As linhas da planilha não mudam de lugar: muda o conteúdo (tipo, carga, reps, notas e descanso). Uma série que termina em drop ou rest-pause sem a parte seguinte precisa ficar por último. No VoiceOver, as ações "Subir série" e "Descer série" fazem o mesmo.
- **Opções da série:** tipo, repetir a última, descanso, limpar e remover ficam no painel de edição, abaixo da Entrada Rápida, e também no toque longo em cada série.
- **Séries:** concluídas ficam com fundo `surface-container-high`, badge preenchido na cor do tipo e check verde; séries com valores preenchidos e não salvos aparecem como "pré-definida" em índigo.
- **Tempo de treino:** cronômetro no topo da tela de treino enquanto o treino de hoje está aberto; some quando o treino é finalizado. O botão Pausar para a contagem (o tempo fica parado em cinza, com "Pausado") e Continuar volta a contar sem incluir o tempo parado. Registrar uma série com o cronômetro pausado volta a contar.
- **Drop e rest-pause:** no painel, escolher Drop ou Rest-pause abre as partes da série (drops ou mini-séries) e um campo de pausa (− valor +, de 5 em 5 s). No topo da Entrada Rápida, uma fileira de botões (`3 · 3.1 · 3.2 · +`, cada um com carga×reps) escolhe o que os steppers grandes e os atalhos editam: a série ou uma das partes, selecionada em índigo. Embaixo, as partes aparecem como resumo grande; tocar abre a parte no topo. Nas mini-séries do rest-pause, os atalhos de reps são baixos (2 a 6). Um drop novo vem com cerca de 20% a menos de carga, arredondado no passo da unidade, e as mesmas reps; uma mini-série nova repete a carga. Salvar grava a série e as partes de uma vez, com a pausa em todas menos na última. A pausa inicial é a da última vez que o exercício teve aquele tipo; sem histórico, 10 s no drop e 15 s no rest-pause.
- **Painel de série:** carga e reps em largura total (teclas de 56 pt, números de 40 pt), tipo, drops ou mini-séries do rest-pause, repetir a última e descanso; a barra de descanso continua visível no painel.
- **Configurar:** lista de treinos agrupada em Vigentes, Programados e Encerrados. No treino: nome e vigência (início e fim opcionais) e os exercícios, que se reordenam em Reordenar e saem com o gesto de deslizar. No exercício: uma linha por série com o badge do tipo, o menu de tipo e − reps +, mais descanso alvo, unidade e notas. Com alterações não salvas, o botão de voltar vira Descartar e o Salvar aparece fixo embaixo.
- **Histórico:** o treino de hoje ainda não finalizado mostra "em andamento" em índigo no lugar da variação de volume, que só aparece depois de Finalizar.
- **Notas do exercício:** aparecem na tela de treino, logo abaixo da última vez, com um ícone de informação.
