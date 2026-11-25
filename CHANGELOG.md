# Changelog

O que mudou no Gimmy, do mais recente para o mais antigo. Todo commit acrescenta aqui uma linha, sob a data do dia.

## 2026-11-25

- Changelog criado, com o histórico desde a primeira versão.

## 2026-11-24

- README: deixa claro que é um app pessoal, só para o controle dos meus treinos, e tira as instruções de instalação e configuração.

## 2026-11-23

- CI: cada build passou a ser publicado como release, com uma fonte para o SideStore. Desfeito no mesmo dia: a atualização continua manual, pelo Sideloadly.

## 2026-11-21

- Placas como unidade de carga, ao lado de kg e lb: seletor KG | LBS | PLACAS, − e + de uma em uma placa, atalhos de +1 a +5 e drop sugerido em placas inteiras.
- Volume: cada placa conta 4,5 kg (estimativa), no app e na fórmula de volume da planilha.
- Testes: corrige o 1RM esperado em placas.

## 2026-11-20

- Reordenar séries segurando e arrastando. A série vai junto com seus drops ou mini-séries, e as demais mantêm a ordem.
- A configuração do treino acompanha a nova ordem, para o próximo treino copiado sair igual.
- Ao finalizar um treino que mudou em relação à configuração, o app pergunta se quero montar uma rotina nova a partir dele (nova versão, valendo a partir do dia seguinte).
- Integridade das rotinas: só uma rotina por grupo muscular vale em cada dia; quando duas se sobrepõem, a mais antiga termina na véspera da nova.

## 2026-11-18

- Drop: os drops entram junto com a série, no mesmo painel, com carga e reps de cada um e a pausa entre eles.
- Drops e mini-séries do rest-pause usam os mesmos controles grandes da série, escolhendo a parte numa fileira no topo do card.

## 2026-11-16

- Histórico: o treino de hoje ainda não finalizado mostra "em andamento" no lugar da variação de volume.
- Prints do README: a barra de descanso aparece só no primeiro.
- Remove a camada de dados da tela de evolução, que não chegou a ser feita.
- Prints do README atualizados.
- Botões de pausar e continuar o cronômetro do treino.
- Prints do README atualizados.
- Botão de recolher o exercício aberto.
- Rest-pause: uma pausa só, gravada na série e em cada mini-série, menos na última.

## 2026-11-12

- Tipo de série Rest-pause.
- Traz as demais mudanças do artefato Registro de Treino.
- Visual Kinetic Dark Minimal.
- Card de entrada rápida fixo no rodapé da tela de treino (desfeito no mesmo dia).
- Camada de dados da tela de evolução (removida em 16/11).
- A série é escolhida tocando na linha dela.
- O editor de série volta a abrir como painel.
- Tira o cadeado dos exercícios ainda não começados.
- Editor e lista: séries concluídas mais destacadas, valores não salvos guardados ao fechar o painel, descanso continua correndo durante a edição, rest-pause inteiro no mesmo painel e teclado numérico no descanso. Primeiros testes unitários.
- Cronômetro do tempo total do treino.
- As séries registradas ficam sincronizadas com a planilha, inclusive depois de uma falha de conexão.
- Configuração de treinos, exercícios e séries, com vigência. O seletor mostra só os treinos vigentes, e um dia sem treino começa com uma cópia do treino configurado, sem as cargas.
- README: aviso de projeto pessoal e prints das telas.
- O último exercício fecha com o check quando todas as séries estão registradas.
- Prints do README atualizados.

## 2026-11-11

- Primeira versão: app nativo de iPhone (SwiftUI) do Registro de Treino, lendo e gravando na planilha Controle de Treinos.
