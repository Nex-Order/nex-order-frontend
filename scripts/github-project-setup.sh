#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Nex Order Frontend - cria labels, milestones, issues e o GitHub Project
# com as ações do plano descrito em docs/PLANO_DE_ACAO.md.
#
# Pré-requisitos:
#   - GitHub CLI >= 2.42 (https://cli.github.com/)
#   - gh auth login && gh auth refresh -s project,read:project
#
# Uso (Linux/macOS ou Git Bash no Windows):
#   DRY_RUN=1 bash scripts/github-project-setup.sh   # só mostra o que faria
#   bash scripts/github-project-setup.sh             # executa
#
# Variáveis opcionais:
#   REPO            repositório alvo        (padrão: martinssluis/nex-order-frontend)
#   OWNER           dono do projeto         (padrão: dono do REPO)
#   PROJECT_TITLE   título do projeto       (padrão: "Nex Order - Frontend")
#   PROJECT_NUMBER  usa um projeto existente em vez de procurar/criar pelo título
#
# Idempotente: labels são atualizadas (--force); milestones e issues com o
# mesmo título não são recriados, apenas (re)adicionados ao projeto.
# -----------------------------------------------------------------------------
set -euo pipefail

REPO="${REPO:-martinssluis/nex-order-frontend}"
OWNER="${OWNER:-${REPO%%/*}}"
PROJECT_TITLE="${PROJECT_TITLE:-Nex Order - Frontend}"
PROJECT_NUMBER="${PROJECT_NUMBER:-}"
DRY_RUN="${DRY_RUN:-0}"

M0="Sprint 0 - Estabilização"
M1="Sprint 1 - Fundação e TypeScript"
M2="Sprint 2 - Autenticação e integração com API"
M3="Sprint 3 - UX, i18n e performance"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[aviso]\033[0m %s\n' "$*" >&2; }

# ----------------------------------------------------------------------------
# Pré-checagens
# ----------------------------------------------------------------------------
if [[ "$DRY_RUN" != "1" ]]; then
  command -v gh >/dev/null || { echo "GitHub CLI (gh) não encontrado: https://cli.github.com/" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "Rode 'gh auth login' antes." >&2; exit 1; }
fi

# ----------------------------------------------------------------------------
# Labels  (nome|cor|descrição)
# ----------------------------------------------------------------------------
LABELS=(
  "prioridade:P0|b60205|Bloqueia uso ou exibe dado incorreto"
  "prioridade:P1|d93f0b|Fundação ou entrega de valor do próximo ciclo"
  "prioridade:P2|fbca04|Melhoria"
  "tipo:bug|d73a4a|Comportamento incorreto"
  "tipo:feature|0e8a16|Nova funcionalidade"
  "tipo:refactor|5319e7|Melhoria interna sem mudança de comportamento"
  "tipo:chore|c5def5|Tooling, configuração, manutenção"
  "tipo:test|bfd4f2|Testes automatizados"
  "tipo:ci|1d76db|Integração contínua"
  "tipo:epic|3e4b9e|Agrupa várias issues"
  "area:typescript|3178c6|Migração JS -> TS"
  "area:auth|7057ff|Autenticação e autorização"
  "area:api|0052cc|Camada de serviços / integração"
  "area:i18n|c2e0c6|Internacionalização"
  "area:ui|e99695|Layout, tema e componentes visuais"
  "area:a11y|f9d0c4|Acessibilidade"
  "area:perf|fef2c0|Performance"
  "area:dx|d4c5f9|Experiência de desenvolvimento"
  "area:dashboard|bfdadc|Módulo Dashboard"
  "area:colaboradores|bfdadc|Módulo Colaboradores"
  "area:estoque|bfdadc|Módulo Estoque"
  "area:financeiro|bfdadc|Módulo Financeiro"
  "area:configuracoes|bfdadc|Módulo Configurações"
)

log "Criando/atualizando labels em $REPO"
for entry in "${LABELS[@]}"; do
  IFS='|' read -r name color desc <<<"$entry"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [dry-run] label: $name"
  else
    gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force >/dev/null
    echo "  label: $name"
  fi
done

# ----------------------------------------------------------------------------
# Milestones
# ----------------------------------------------------------------------------
log "Criando milestones"
EXISTING_MILESTONES=""
if [[ "$DRY_RUN" != "1" ]]; then
  EXISTING_MILESTONES="$(gh api "repos/$REPO/milestones?state=all&per_page=100" --jq '.[].title')"
fi

create_milestone() {
  local title="$1" desc="$2"
  if grep -Fxq -- "$title" <<<"$EXISTING_MILESTONES"; then
    echo "  milestone já existe: $title"
  elif [[ "$DRY_RUN" == "1" ]]; then
    echo "  [dry-run] milestone: $title"
  else
    gh api -X POST "repos/$REPO/milestones" -f title="$title" -f description="$desc" >/dev/null
    echo "  milestone: $title"
  fi
}

create_milestone "$M0" "Corrigir bugs que exibem dados incorretos ou quebram telas; lint sem erros."
create_milestone "$M1" "Tooling, CI, testes, migração para TypeScript e reorganização do código."
create_milestone "$M2" "Login real, rotas protegidas, camada de dados e integração dos módulos com a API."
create_milestone "$M3" "i18n completo, code-splitting, acessibilidade e estados de UX."

# ----------------------------------------------------------------------------
# Projeto
# ----------------------------------------------------------------------------
if [[ "$DRY_RUN" == "1" ]]; then
  PROJECT_NUMBER="${PROJECT_NUMBER:-<novo>}"
  log "[dry-run] Projeto: $PROJECT_TITLE (#$PROJECT_NUMBER) de $OWNER"
else
  if [[ -z "$PROJECT_NUMBER" ]]; then
    PROJECT_NUMBER="$(gh project list --owner "$OWNER" --limit 100 --format json \
      --jq ".projects[] | select(.title == \"$PROJECT_TITLE\") | .number" | head -n1)"
  fi
  if [[ -z "$PROJECT_NUMBER" ]]; then
    PROJECT_NUMBER="$(gh project create --owner "$OWNER" --title "$PROJECT_TITLE" --format json --jq '.number')"
    log "Projeto criado: $PROJECT_TITLE (#$PROJECT_NUMBER)"
    gh project link "$PROJECT_NUMBER" --owner "$OWNER" --repo "$REPO" >/dev/null 2>&1 \
      || warn "Não foi possível vincular o projeto ao repositório (faça pela UI se quiser)."
  else
    log "Usando projeto existente #$PROJECT_NUMBER"
  fi
fi

# ----------------------------------------------------------------------------
# Issues
# ----------------------------------------------------------------------------
EXISTING_ISSUES=""
if [[ "$DRY_RUN" != "1" ]]; then
  EXISTING_ISSUES="$(gh issue list --repo "$REPO" --state all --limit 1000 \
    --json number,title --jq '.[] | "\(.number)\t\(.title)"')"
fi

DRY_COUNTER=0

# issue <ID> <título> <labels separados por vírgula> <milestone>   (corpo via stdin)
# Guarda o número criado em ISSUE_<ID> para referência posterior (ex.: épico).
issue() {
  local id="$1" title="$2" labels="$3" milestone="$4" body number url
  body="$(cat)"

  if [[ "$DRY_RUN" == "1" ]]; then
    DRY_COUNTER=$((DRY_COUNTER + 1))
    printf -v "ISSUE_$id" '%s' "$DRY_COUNTER"
    echo "  [dry-run] #$DRY_COUNTER [$milestone] $title  ($labels)"
    return
  fi

  number="$(awk -F'\t' -v t="$title" '$2 == t { print $1; exit }' <<<"$EXISTING_ISSUES")"
  if [[ -n "$number" ]]; then
    echo "  já existe #$number: $title"
    url="https://github.com/$REPO/issues/$number"
  else
    url="$(gh issue create --repo "$REPO" --title "$title" --label "$labels" \
      --milestone "$milestone" --body-file - <<<"$body")"
    number="${url##*/}"
    echo "  criada #$number: $title"
  fi
  printf -v "ISSUE_$id" '%s' "$number"

  gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "$url" >/dev/null \
    || warn "Falha ao adicionar #$number ao projeto."
}

# ============================================================================
# Sprint 0 - Estabilização
# ============================================================================
log "Issues - $M0"

issue B1 "fix(dashboard): clique em Itens populares lança ReferenceError (onSelect indefinido)" \
  "tipo:bug,prioridade:P0,area:dashboard" "$M0" <<'EOF'
## Contexto
`src/components/PopularList/PopularList.jsx:25` chama `onSelect(item)`, mas `onSelect` não é prop nem variável. Qualquer clique num item gera `ReferenceError`. O gráfico "Histórico de saída" do Dashboard sempre mostra o **primeiro item filtrado** (`Dashboard.jsx:119`), sem seleção real.

## O que fazer
- Receber `onSelect` e `selectedId` como props em `PopularList` e destacar o item selecionado.
- Guardar o produto selecionado em estado no `Dashboard`, com a busca apenas filtrando a lista.
- Usar `item.id` como `key` em vez do índice.

## Critérios de aceite
- [ ] Clicar em um item atualiza o gráfico "Histórico de saída" com aquele produto.
- [ ] Nenhum erro no console ao clicar.
- [ ] `npm run lint` sem o erro `no-undef` em PopularList.
EOF

issue B2 "fix(colaboradores): indicadores do painel exibem 0/NaN (campos e cálculos errados)" \
  "tipo:bug,prioridade:P0,area:colaboradores" "$M0" <<'EOF'
## Contexto
Em `src/pages/Employees/EmployeesDash.jsx:161-176`:
- `totalAtivos`/`totalInativos` filtram por `c.ativo`, mas as linhas têm `active`, então **Ativos = 0 e Inativos = todos**.
- `totalFolha`/`mediaSalarial` somam `c.salarioBase`, mas a linha tem `baseSalary`, então o resultado é **NaN**.
- `mediaPorCargo = rows / totalRoles` divide um array por número e dá **NaN**.
- `mediaSalarial` divide por zero com a lista vazia.
- As tendências ("+2%", "-2%") são valores fixos e enganam o usuário.

## O que fazer
- Corrigir os campos e extrair os cálculos para funções puras testáveis (`src/features/employees/metrics`).
- Proteger as divisões por zero.
- Remover as tendências fixas até haver dado real (ou ocultar a prop `trend`).
- Formatar moeda com `Intl.NumberFormat`.

## Critérios de aceite
- [ ] Os cards mostram os valores corretos para os dados da API.
- [ ] Com a lista vazia, os cards mostram 0 / "R$ 0,00" (nunca NaN).
- [ ] Testes unitários dos cálculos (após setup do Vitest).
EOF

issue B3 "fix(colaboradores): mapeamento da API usa índice como id e campo de status inconsistente" \
  "tipo:bug,prioridade:P0,area:colaboradores,area:api" "$M0" <<'EOF'
## Contexto
`src/pages/Employees/EmployeesDash.jsx:139-160`:
- `id: index + 1` em vez do id do backend inviabiliza editar e excluir.
- Lê `emp.isActive`, mas o cadastro (`Employees.jsx:49`) envia `active`. É preciso confirmar o contrato com o backend.
- O erro é engolido (`console.error`): não há estado de carregamento, de erro nem de lista vazia.
- `loadEmployees` é usada antes de ser declarada (erro `react-hooks/immutability`).
- `console.log` de debug.
- O campo "Pesquisar" (linha 282) não faz nada.

## Critérios de aceite
- [ ] `id` vem do backend.
- [ ] Contrato de status (`active` × `isActive`) alinhado com o backend e documentado.
- [ ] Estados de carregamento, erro e vazio visíveis na tela.
- [ ] Busca filtra a tabela por nome/e-mail.
- [ ] Sem `console.log` e sem erros de lint no arquivo.
EOF

issue B4 "fix(colaboradores): campo Cargo envia tipos diferentes e formulário tem props inválidas" \
  "tipo:bug,prioridade:P0,area:colaboradores" "$M0" <<'EOF'
## Contexto
`src/pages/Employees/Employees.jsx`:
- `role` começa como `1` (número, linha 21), as opções do select são strings ("Vendedor", "Gestor", "Estagiário"), e o reset volta para `''` (linha 79). O backend recebe tipos diferentes conforme o caminho, e o select abre sem nenhuma opção válida selecionada.
- `bgcolor: 'background.defaut'` (erro de digitação, linha 93).
- `fullWidth={200}` (é booleano, linha 194).
- `rows={3}` em campo que não é `multiline` (linha 148).
- `console.log('Criado:')` e textos fixos em português (as chaves `pages.employees.*` já existem).
- Após cadastrar, a página não volta à listagem.

## Critérios de aceite
- [ ] Os valores de `role` vêm de um enum/constante alinhada ao backend, com valor inicial e reset coerentes.
- [ ] As props inválidas foram corrigidas.
- [ ] Após sucesso, o usuário vê feedback e pode voltar à listagem (ou é redirecionado).
EOF

issue B5 "fix(configuracoes): ícone do tema não aparece e componente é recriado a cada render" \
  "tipo:bug,prioridade:P0,area:configuracoes" "$M0" <<'EOF'
## Contexto
`src/pages/Settings/Settings.jsx:61-65` declara `IconTheme` dentro do render com `(props => { <Icon .../> })`. A função não tem `return`, então retorna `undefined` e **o ícone nunca é exibido**. O ESLint aponta `react-hooks/static-components`.

## O que fazer
Renderizar `<Icon name={isDark ? 'darkModeOutlinedIcon' : 'lightModeOutlinedIcon'} sx={...} />` diretamente.

## Critérios de aceite
- [ ] Os ícones de sol/lua aparecem nos cards de preview.
- [ ] Sem erro de lint no arquivo.
EOF

issue B6 "fix(api): apiFetch perde Content-Type ao receber headers; env ausente derruba o app" \
  "tipo:bug,prioridade:P0,area:api" "$M0" <<'EOF'
## Contexto
`src/service/api.js`:
- `...options` é espalhado **depois** de `headers` (linhas 10-15). Se a chamada passar `options.headers` (por exemplo, `Authorization`), o `Content-Type` mesclado é sobrescrito.
- `console.log("API URL:")` em produção (linha 2).
- `throw` no import do módulo quando falta `VITE_API_URL`. Como todas as páginas são importadas de forma estática, **o app inteiro (inclusive o Login) quebra**.
- O erro da API vira `Error(texto cru)`, sem status HTTP.

## O que fazer
- Montar `{ ...options, headers: { 'Content-Type': 'application/json', ...options.headers } }`.
- Validar a env de forma preguiçosa (na primeira chamada) ou em um módulo `config` com mensagem clara.
- Criar a classe `ApiError` com `status` e `body`.
- Adicionar `.env.example` com `VITE_API_URL=` e documentar no README.

## Critérios de aceite
- [ ] Headers customizados preservam o `Content-Type`.
- [ ] Sem `VITE_API_URL`, o Login abre e as telas que chamam a API mostram erro amigável.
- [ ] `.env.example` versionado.
EOF

issue B7 "fix(auth): logout apaga preferências de tema e idioma (localStorage.clear)" \
  "tipo:bug,prioridade:P0,area:auth" "$M0" <<'EOF'
## Contexto
`src/components/SideBar/SwipeableDrawer.jsx:65` chama `localStorage.clear()` e `sessionStorage.clear()`, o que remove `authThemeMode` e `authLanguage`.

## Critérios de aceite
- [ ] O logout remove apenas os dados de sessão (token/usuário).
- [ ] Tema e idioma permanecem após sair e entrar novamente.
EOF

issue B8 "fix(layout): larguras de sidebar/header/conteúdo inconsistentes e overflow horizontal" \
  "tipo:bug,prioridade:P0,area:ui" "$M0" <<'EOF'
## Contexto
- Sidebar com 80/200 px (`SwipeableDrawer.jsx:76`), margem do conteúdo com 80/**240** px (`AppLayout.jsx:33`) e recuo do logo com 65/190 px (`Header.jsx:50`): com o menu expandido sobra uma faixa de 40 px.
- `Card` com `width: 2000` fixo em `EmployeesDash.jsx:279` causa scroll horizontal.
- `<Grid item>` fora de `<Grid container>` em `EmployeesDash.jsx:187` e `StockDash.jsx:53`.

## O que fazer
Centralizar as larguras em constantes (`SIDEBAR_WIDTH`, `SIDEBAR_COLLAPSED_WIDTH`) usadas pelos três componentes, e remover larguras fixas.

## Critérios de aceite
- [ ] Sem faixa vazia entre a sidebar e o conteúdo (recolhida e expandida).
- [ ] Sem scroll horizontal em 360 px, 768 px, 1280 px e 1920 px.
EOF

issue B9 "fix(graficos): keys ausentes, linha fixa 'value2', gradiente global e tooltip ignorando tema" \
  "tipo:bug,prioridade:P1,area:ui" "$M0" <<'EOF'
## Contexto
- `ChartCard.jsx`: `map` sem `key`. `<Line dataKey="value2">` é sempre renderizada. Todas as linhas usam a mesma cor. O import de `Card` não é usado, e o componente exporta `Chart`, mas o arquivo se chama `ChartCard`.
- `ChartColumn.jsx`: `map` sem `key`. `type="monotone"` não se aplica a `<Bar>`. O id `barGradient` é global e colide com dois gráficos na mesma tela.
- `DonutChart`/`ChartCard`/`ChartColumn`: tooltip com fundo `#1e1e1e` fixo, ilegível no padrão visual do tema claro.
- `ChartIndicators.jsx`: divisão por zero quando o total é 0, e há um bloco comentado (código morto).
- `StatCard.jsx`: `variant="subtitle"` não existe no MUI (usar `subtitle1`/`subtitle2`).

## Critérios de aceite
- [ ] Cada linha/barra recebe cor e `key` próprias, a partir de uma prop.
- [ ] Tooltip usa cores do tema (`theme.palette`).
- [ ] Ids de gradiente únicos (`useId`).
- [ ] Sem warnings de key no console.
EOF

issue B10 "fix(textos): corrigir rótulos e unidades incorretos" \
  "tipo:bug,prioridade:P1,area:ui" "$M0" <<'EOF'
## Contexto
- "Despezas" → "Despesas" (`Financial.jsx:195`).
- "Entre no NO" (`Login.jsx:20`) → "Entre no NexOrder".
- "Média de saídas/entradas" exibidas com `%`, mas não são percentuais (`StockDash.jsx:117,131`).
- "Total de produtos" soma unidades em estoque, não produtos (`StockDash.jsx:18`). Renomear para "Itens em estoque" ou contar produtos.
- Imagens sem `alt` (`Login.jsx`, `HeaderLogin.jsx`, `Header.jsx`); a chave `header.logoAlt` existe e não é usada.
- `index.html` com `lang="en"`.

## Critérios de aceite
- [ ] Todos os itens acima corrigidos.
EOF

issue B11 "chore(lint): zerar erros do ESLint e remover código morto" \
  "tipo:chore,prioridade:P0,area:dx" "$M0" <<'EOF'
## Contexto
`npm run lint` aponta hoje 6 erros e 1 aviso. Código morto:
- `src/components/MainContent/MainContent.jsx` importa `../SideBar/SideBar`, que não existe.
- `colaboradoresMock` sem uso (`EmployeesDash.jsx:10`).
- Bloco comentado em `ChartIndicators.jsx`.
- Prop `title` passada ao `DonutChart`, que a ignora.
- `react-refresh/only-export-components` nos providers: separar os hooks `useAuthTheme`/`useAuthLanguage` em arquivos próprios.

## Critérios de aceite
- [ ] `npm run lint` termina sem erros e sem avisos.
- [ ] Arquivos e trechos mortos removidos.
- [ ] Nenhum `console.log` em `src/` (regra `no-console: warn`).
EOF

# ============================================================================
# Sprint 1 - Fundação e TypeScript
# ============================================================================
log "Issues - $M1"

issue F1 "chore(dx): padronizar tooling (Prettier, EditorConfig, husky, lint-staged, package.json, README)" \
  "tipo:chore,prioridade:P1,area:dx" "$M1" <<'EOF'
## O que fazer
- Prettier + `eslint-config-prettier` e um commit de formatação geral.
- `.editorconfig`.
- husky + lint-staged rodando lint/format nos arquivos staged.
- `package.json`: `"name": "nex-order-frontend"`, versão `0.1.0`, `engines.node` e scripts `format`, `typecheck` e `test`.
- `.nvmrc` com a versão do Node.
- README: nome NexOrder, `.env`, scripts, convenção de commits (Conventional Commits, já usada) e fluxo de branches (`feature/*` → `develop`).
- Decidir sobre a alteração não commitada no `package-lock.json`.

## Critérios de aceite
- [ ] `npm run format:check` passa no repositório inteiro.
- [ ] Pre-commit bloqueia arquivos com erro de lint.
EOF

issue F2 "ci: pipeline no GitHub Actions (lint, typecheck, test, build) nos PRs" \
  "tipo:ci,prioridade:P1,area:dx" "$M1" <<'EOF'
## O que fazer
Workflow `.github/workflows/ci.yml` em `pull_request` e `push` para `develop`/`main`:
`npm ci` → `lint` → `typecheck` → `test` → `build`, com cache de npm e Node da `.nvmrc`.

## Critérios de aceite
- [ ] O CI roda em todo PR.
- [ ] Proteção de branch na `develop` exigindo o CI verde e 1 review.
EOF

issue F3 "test: configurar Vitest + Testing Library e primeiros testes" \
  "tipo:test,prioridade:P1,area:dx" "$M1" <<'EOF'
## O que fazer
- Vitest + jsdom + `@testing-library/react` + `@testing-library/user-event`.
- Primeiros testes:
  - `useI18n` (fallback para pt-BR e para a própria chave).
  - `apiFetch` (headers, erro, corpo vazio).
  - Cálculos dos indicadores de Colaboradores/Estoque/Financeiro.
  - `PopularList` (seleção).
- Relatório de cobertura no CI.

## Critérios de aceite
- [ ] `npm test` roda localmente e no CI.
- [ ] Os testes acima passam.
EOF

issue T1 "ts(setup): configurar TypeScript no projeto com allowJs (migração incremental)" \
  "tipo:chore,prioridade:P1,area:typescript" "$M1" <<'EOF'
## O que fazer
- Instalar `typescript` e `typescript-eslint`.
- Criar `tsconfig.json`, `tsconfig.app.json` e `tsconfig.node.json` (modelo do template `react-ts` do Vite) com `strict: true`, `allowJs: true`, `jsx: react-jsx` e `moduleResolution: bundler`.
- `src/vite-env.d.ts` tipando `ImportMetaEnv` (`VITE_API_URL: string`).
- Converter `vite.config.js` → `vite.config.ts` e `eslint.config.js` com regras do `typescript-eslint` para `**/*.{ts,tsx}`.
- Script `"typecheck": "tsc -b --noEmit"` e passo no CI.
- Configurar o alias `@/` → `src/` (tsconfig + vite).

## Critérios de aceite
- [ ] `npm run typecheck`, `lint` e `build` passam sem nenhum arquivo convertido ainda.
- [ ] Um arquivo `.tsx` novo pode importar um `.jsx` existente e vice-versa.
EOF

issue T2 "ts(dominio): criar tipos de domínio em src/types" \
  "tipo:refactor,prioridade:P1,area:typescript" "$M1" <<'EOF'
## O que fazer
Definir, alinhado com os DTOs do backend:
- `Employee`, `CreateEmployeeDTO`, `Role` (enum/union igual ao backend).
- `Product`, `StockMovement`.
- `FinancialTransaction` (`type: 'income' | 'expense'`, `status: 'paid' | 'pending'`).
- `ApiError`.
- Padronizar os nomes de campos em inglês (hoje há `nome`/`valor`/`percentual` misturados com `name`/`value`).

## Critérios de aceite
- [ ] Tipos revisados com o time de backend.
- [ ] Mocks existentes tipados com esses tipos.
EOF

issue T3 "ts(api): migrar camada de serviços para TypeScript" \
  "tipo:refactor,prioridade:P1,area:typescript,area:api" "$M1" <<'EOF'
## O que fazer
- `src/service/api.js` → `src/services/api.ts` com `apiFetch<T>(endpoint, options): Promise<T>`.
- Classe `ApiError` (`status`, `body`).
- `employeeService.ts` tipado com `Employee` e `CreateEmployeeDTO`.

## Critérios de aceite
- [ ] Serviços sem `any`.
- [ ] Testes do `apiFetch` passando.
EOF

issue T4 "ts(i18n): migrar i18n com chaves tipadas e contextos de preferências" \
  "tipo:refactor,prioridade:P1,area:typescript,area:i18n" "$M1" <<'EOF'
## O que fazer
- `translations.ts` com `as const satisfies`, garantindo que `en` tenha as mesmas chaves de `pt-BR`.
- Tipo `TranslationKey` derivado das chaves (dot-notation): `t('chave.inexistente')` passa a ser erro de compilação.
- Migrar `AuthLanguageProvider`/`AuthThemeProvider` e renomeá-los para `PreferencesProvider` (ou `LanguageProvider`/`ThemeModeProvider`), porque não têm relação com autenticação. Manter as chaves de `localStorage` compatíveis.

## Critérios de aceite
- [ ] Chave de tradução inválida falha no `typecheck`.
- [ ] Preferências salvas antes da migração continuam funcionando.
EOF

issue T5 "ts(componentes): migrar componentes compartilhados para .tsx" \
  "tipo:refactor,prioridade:P1,area:typescript" "$M1" <<'EOF'
## Escopo
Header, Sidebar, StatCard, DataTable, ChartCard, ChartColumn, DonutChart, ChartIndicators, PopularList, RankList, IconLibrary.

## O que fazer
- Interface de props exportada por componente.
- `Icon` com `name: IconName` (união das chaves do mapa).
- Generics no `DataTable<Row>` com `GridColDef<Row>`.

## Critérios de aceite
- [ ] Nenhum `any` implícito.
- [ ] O comportamento visual não muda.
EOF

issue T6 "ts(paginas): migrar páginas, layouts e main para .tsx" \
  "tipo:refactor,prioridade:P1,area:typescript" "$M1" <<'EOF'
## Escopo
Dashboard, Financial, Employees, EmployeesDash, Stock, StockDash, Settings, Login, HeaderLogin, AppLayout, PublicLayout e `main.jsx` → `main.tsx` (atualizar `index.html`).

## Critérios de aceite
- [ ] Nenhum `.js`/`.jsx` restante em `src/`.
- [ ] Todas as rotas funcionam como antes (smoke test manual + testes).
EOF

issue T7 "ts(strict): remover allowJs e endurecer o compilador" \
  "tipo:chore,prioridade:P1,area:typescript" "$M1" <<'EOF'
## O que fazer
- Remover `allowJs`.
- Ativar `noUncheckedIndexedAccess`, `noImplicitOverride`, `noUnusedLocals` e `noUnusedParameters`.
- ESLint: `@typescript-eslint/no-explicit-any: error` e bloqueio de novos `.js`/`.jsx` em `src/`.
- README atualizado (stack e convenções TS).

## Critérios de aceite
- [ ] `typecheck`, `lint`, `test` e `build` verdes no CI.
EOF

issue F4 "refactor(estrutura): reorganizar pastas e padronizar nomes" \
  "tipo:refactor,prioridade:P1,area:dx" "$M1" <<'EOF'
## O que fazer
Proposta de estrutura:
```
src/
  app/          (router, providers, main)
  components/   (componentes genéricos de UI)
  features/     (employees/, stock/, financial/, dashboard/, auth/, settings/
                 cada um com pages/, components/, api/, hooks/, types)
  services/     (api client)
  i18n/  theme/  types/  mocks/
```
- Renomear: `SideBar/SwipeableDrawer.jsx` → `Sidebar/Sidebar`; `Chart/ChartCard` → `LineChartCard`; `chartcolors` → `theme/chartColors`; `service` → `services`.
- Rotas em constantes (`ROUTES.employees.list`), sem strings soltas em `navigate()`.
- Código (variáveis, campos) em inglês; textos de UI via i18n.

## Critérios de aceite
- [ ] Estrutura documentada no README.
- [ ] Imports usando o alias `@/`.
EOF

issue F5 "refactor(tema): centralizar design tokens e corrigir reset CSS/foco" \
  "tipo:refactor,prioridade:P1,area:ui,area:a11y" "$M1" <<'EOF'
## Contexto
- Há cores fixas espalhadas (`#3b70ab`, `#5a50e7`, `#1e1e1e`…) e um bloco `sx` do StatCard copiado 6 vezes.
- `App.css` duplica o `CssBaseline` e aplica `outline: none` em botões e inputs, o que remove o foco visível.
- A fonte Roboto é carregada via `@import` do Google Fonts no CSS, o que bloqueia a renderização.
- Três estratégias de estilo misturadas (CSS Modules, `sx`, `<input>` HTML puro em Login e Stock).

## O que fazer
- Um `theme.ts` único (cores, raios, sombras, `components` overrides) compartilhado entre os temas claro e escuro, com `PublicLayout` usando o mesmo tema.
- Remover o reset redundante e restaurar `:focus-visible`.
- Fonte via `@fontsource/roboto`.
- Definir a convenção: MUI + `sx`/`styled` como padrão, CSS Modules só quando necessário.

## Critérios de aceite
- [ ] Nenhuma cor hexadecimal fora de `theme/`.
- [ ] Foco visível em todos os elementos interativos.
EOF

issue F6 "refactor: extrair mocks e componentes repetidos (PageHeader, StatGrid)" \
  "tipo:refactor,prioridade:P2,area:ui" "$M1" <<'EOF'
## O que fazer
- Mover os mocks de `Dashboard`, `Financial`, `StockDash` e `EmployeesDash` para `src/mocks/` (ou MSW), tipados.
- Criar `PageHeader` (ícone + título + ação) e `StatGrid` (grade de `StatCard` a partir de um array), eliminando a duplicação.

## Critérios de aceite
- [ ] Nenhum array de dados de negócio declarado dentro de componentes de página.
EOF

# ============================================================================
# Sprint 2 - Autenticação e integração com API
# ============================================================================
log "Issues - $M2"

issue A1 "feat(auth): login real com validação e AuthContext" \
  "tipo:feature,prioridade:P1,area:auth" "$M2" <<'EOF'
## Contexto
Hoje o botão "Entrar" apenas navega para `/app/dashboard` (`Login.jsx:36`). Os inputs não são controlados e não há validação.

## O que fazer
- Formulário controlado (MUI) com validação e mensagens de erro.
- Integração com o endpoint de autenticação do backend.
- `AuthContext` com `user`, `token`, `login()` e `logout()`, e persistência segura do token (alinhar com o backend: cookie httpOnly é preferível a localStorage).
- Estado de carregamento no botão.

## Critérios de aceite
- [ ] Credenciais inválidas mostram erro, e as válidas levam ao Dashboard.
- [ ] Ao recarregar a página, a sessão continua válida.
EOF

issue A2 "feat(auth): proteger rotas /app e tratar sessão expirada (401)" \
  "tipo:feature,prioridade:P1,area:auth,area:api" "$M2" <<'EOF'
## O que fazer
- `ProtectedRoute`/loader no React Router: sem sessão em `/app/*`, redirecionar para `/login?redirect=...`.
- Usuário logado que acessa `/login` vai para o Dashboard.
- `apiFetch` envia `Authorization` e, em 401, faz logout e redireciona.
- Logout limpa apenas os dados de sessão.

## Critérios de aceite
- [ ] Acessar `/app/financial` sem login redireciona ao login e, após entrar, volta para a rota pedida.
EOF

issue A3 "feat(api): camada de dados com TanStack Query e tratamento global de erros" \
  "tipo:feature,prioridade:P1,area:api" "$M2" <<'EOF'
## O que fazer
- `@tanstack/react-query` com `QueryClientProvider`.
- Hooks por feature (`useEmployees`, `useCreateEmployee`…).
- Feedback global de erro/sucesso (Snackbar) e invalidação de cache após mutações.

## Critérios de aceite
- [ ] Nenhuma chamada de API diretamente em `useEffect` nas páginas.
EOF

issue A4 "feat(forms): padronizar formulários com react-hook-form + zod" \
  "tipo:feature,prioridade:P1,area:ui" "$M2" <<'EOF'
## O que fazer
- Schemas `zod` por entidade (tipos TS inferidos via `z.infer`).
- Componentes de campo MUI integrados ao RHF.
- Validações: e-mail, telefone, salário e preço numéricos e positivos, campos obrigatórios.

## Critérios de aceite
- [ ] Os formulários de Login, Colaborador e Produto usam o mesmo padrão.
EOF

issue A5 "feat(colaboradores): CRUD completo integrado à API" \
  "tipo:feature,prioridade:P1,area:colaboradores" "$M2" <<'EOF'
## O que fazer
Listar (com paginação/busca), criar, editar e inativar colaboradores. Cargo vindo do backend. Indicadores calculados com dados reais.

## Critérios de aceite
- [ ] Todas as operações refletem no backend e na tabela sem recarregar a página.
EOF

issue A6 "feat(estoque): cadastro e listagem de produtos integrados à API" \
  "tipo:feature,prioridade:P1,area:estoque" "$M2" <<'EOF'
## Contexto
`Stock.jsx` apenas faz `console.log` no submit, usa `<input>` HTML puro e o preço é texto livre. `StockDash` usa mock.

## O que fazer
- Formulário MUI + RHF/zod: preço numérico em moeda, categoria como select.
- Listagem real com indicadores.
- Registro de entradas e saídas (escopo da 1ª etapa do README).

## Critérios de aceite
- [ ] O produto cadastrado aparece na listagem.
- [ ] Os indicadores refletem os dados reais.
EOF

issue A7 "feat(financeiro): integrar módulo Financeiro à API" \
  "tipo:feature,prioridade:P1,area:financeiro" "$M2" <<'EOF'
## O que fazer
Substituir `financialMock`, `lineData` e `rankData` por dados da API: saldo, pendências, categorias, evolução mensal, top categorias e movimentações com filtro por período.

## Critérios de aceite
- [ ] Nenhum dado mockado na página.
- [ ] Valores formatados em moeda e datas no idioma do usuário.
EOF

issue A8 "feat(dashboard): integrar indicadores do Dashboard à API" \
  "tipo:feature,prioridade:P1,area:dashboard" "$M2" <<'EOF'
## O que fazer
Cards (colaboradores, pagamentos pendentes, produtos, total de vendas), vendas por mês e histórico de saída por produto vindos da API.

## Critérios de aceite
- [ ] Nenhum dado mockado no Dashboard.
EOF

# ============================================================================
# Sprint 3 - UX, i18n e performance
# ============================================================================
log "Issues - $M3"

issue U1 "feat(i18n): traduzir todas as telas e formatar moeda/número/data com Intl" \
  "tipo:feature,prioridade:P2,area:i18n" "$M3" <<'EOF'
## Contexto
Telas com textos fixos em português: Employees, EmployeesDash, StockDash, Financial, Login, HeaderLogin e Header ("Seu Perfil"). Cabeçalhos das tabelas e meses do gráfico financeiro também. O idioma só existe na área logada, porque os providers envolvem apenas `/app`.

## O que fazer
- Mover todos os textos para `translations`.
- Helpers `formatCurrency`, `formatNumber` e `formatDate` com `Intl` respeitando o idioma.
- Providers de preferências na raiz (também nas rotas públicas).
- `document.documentElement.lang` sincronizado com o idioma.

## Critérios de aceite
- [ ] Trocar para inglês traduz 100% das telas.
- [ ] Valores monetários com separadores corretos.
EOF

issue U2 "perf: code-splitting por rota (bundle atual de 1,46 MB)" \
  "tipo:refactor,prioridade:P2,area:perf" "$M3" <<'EOF'
## Contexto
O `vite build` gera um único chunk de 1.465 KB (448 KB gzip), com alerta do Vite. A tela de Login carrega MUI DataGrid e Recharts sem precisar.

## O que fazer
- `lazy` nas rotas do React Router (ou `React.lazy` + `Suspense` com fallback).
- `manualChunks` para vendor (react, mui, recharts, x-data-grid).

## Critérios de aceite
- [ ] Nenhum chunk acima de 500 KB.
- [ ] A rota de Login carrega menos de 200 KB gzip.
EOF

issue U3 "a11y: auditoria de acessibilidade e navegação" \
  "tipo:feature,prioridade:P2,area:a11y" "$M3" <<'EOF'
## O que fazer
- `aria-label` nos `IconButton` (menu, recolher sidebar, avatar).
- `alt` em todas as imagens.
- Labels associados aos inputs (Login e Stock usam só placeholder).
- Contraste nos dois temas.
- Navegação por teclado (cards de tema em Settings são `Paper` clicáveis e não recebem foco).
- Destaque da rota ativa na Sidebar (`NavLink`).

## Critérios de aceite
- [ ] Lighthouse Accessibility ≥ 90 em todas as rotas.
EOF

issue U4 "feat(ux): estados de carregamento/vazio/erro, página 404 e responsividade" \
  "tipo:feature,prioridade:P2,area:ui" "$M3" <<'EOF'
## O que fazer
- Skeletons/spinners, mensagens de lista vazia e de erro com "tentar novamente".
- Página 404 (hoje `*` redireciona silenciosamente ao Login).
- Revisar tabelas e cards em telas pequenas (DataGrid com scroll interno, cards em 1 coluna no mobile).

## Critérios de aceite
- [ ] Todas as telas com dados remotos têm os 3 estados.
- [ ] Uma rota inexistente mostra a página 404 com link para o início.
EOF

issue U5 "feat(ux): menu de perfil no Header e links de Ajuda/Contato no Login" \
  "tipo:feature,prioridade:P2,area:ui" "$M3" <<'EOF'
## Contexto
O avatar do Header (`Header.jsx:62-66`) não faz nada. "Ajuda" e "Contato" no `HeaderLogin` são `<li>` sem link.

## O que fazer
- Menu do avatar com nome do usuário, Configurações e Sair.
- Links reais (ou modais) para Ajuda e Contato.

## Critérios de aceite
- [ ] Avatar abre um menu funcional.
- [ ] Ajuda e Contato são navegáveis por teclado.
EOF

# ----------------------------------------------------------------------------
# Épico de migração para TypeScript (criado por último para referenciar filhos)
# ----------------------------------------------------------------------------
log "Épico - Migração para TypeScript"

issue EPIC_TS "epic: migração de JavaScript para TypeScript" \
  "tipo:epic,prioridade:P1,area:typescript" "$M1" <<EOF
## Objetivo
Migrar todo o frontend para TypeScript de forma incremental (\`allowJs\` durante a transição), sem interromper o desenvolvimento das features.

## Por quê
Vários bugs atuais (campos inexistentes nos indicadores de Colaboradores, \`role\` com tipos diferentes, contrato \`active\` × \`isActive\`, divisão de array por número) teriam sido barrados pelo compilador. Com a base ainda pequena (~30 arquivos), o custo é baixo.

## Etapas
- [ ] #${ISSUE_T1} Setup do TypeScript
- [ ] #${ISSUE_T2} Tipos de domínio
- [ ] #${ISSUE_T3} Camada de serviços
- [ ] #${ISSUE_T4} i18n e contextos
- [ ] #${ISSUE_T5} Componentes compartilhados
- [ ] #${ISSUE_T6} Páginas, layouts e main
- [ ] #${ISSUE_T7} Strict total e remoção do allowJs

## Definição de pronto
\`npm run typecheck\`, \`lint\`, \`test\` e \`build\` verdes no CI, e nenhum \`.js\`/\`.jsx\` em \`src/\`.

Detalhes: \`docs/PLANO_DE_ACAO.md\`, seção 4.
EOF

log "Concluído."
if [[ "$DRY_RUN" != "1" ]]; then
  echo "Projeto: https://github.com/users/$OWNER/projects/$PROJECT_NUMBER (ou /orgs/$OWNER/projects/$PROJECT_NUMBER se for organização)"
fi
