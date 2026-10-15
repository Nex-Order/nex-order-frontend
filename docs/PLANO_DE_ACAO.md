# Nex Order Frontend — Revisão Técnica e Plano de Ação

> Revisão feita sobre a branch `develop` (commit `49612a4`) em 12/10/2026.
> Evidências: leitura de todos os arquivos de `src/`, `npm run lint` (7 problemas, 6 erros) e `vite build` (OK, com bundle único de 1,46 MB / 448 KB gzip).
> As tarefas deste plano são criadas no GitHub Projects pelo script [`scripts/github-project-setup.sh`](../scripts/github-project-setup.sh).

---

## 1. Visão geral

O projeto é uma SPA React 19 + Vite 7 + MUI 5 com quatro módulos (Dashboard, Financeiro, Colaboradores, Estoque) e Configurações (tema e idioma). Hoje ele é essencialmente um **protótipo navegável**:

| Módulo        | Situação atual                                                                 |
|---------------|--------------------------------------------------------------------------------|
| Login         | Visual pronto; **não autentica** (o botão apenas navega para `/app/dashboard`) |
| Dashboard     | 100% mock                                                                      |
| Financeiro    | 100% mock                                                                      |
| Estoque       | Lista mock; o cadastro só faz `console.log`                                    |
| Colaboradores | **Único módulo integrado à API** (listar e criar), com bugs nos indicadores    |
| Configurações | Funcional (tema claro/escuro e idioma pt-BR/en)                                |

Pontos positivos: estrutura de rotas aninhadas clara, layouts separados (público × autenticado), contextos de tema e idioma bem implementados (memoizados, validados, persistidos), i18n com fallback, componentes de gráficos e cards reaproveitados entre páginas.

---

## 2. Falhas encontradas

### 2.1 Bugs (comportamento incorreto hoje)

| # | Severidade | Onde | Problema |
|---|-----------|------|----------|
| B1 | **Alta** | `src/components/PopularList/PopularList.jsx:25` | `onSelect` não existe. Clicar em qualquer item de "Itens populares" no Dashboard lança `ReferenceError`. Além disso, o gráfico sempre mostra o primeiro item filtrado: não há seleção real. |
| B2 | **Alta** | `src/pages/Employees/EmployeesDash.jsx:163-176` | Indicadores calculados com campos que não existem nas linhas: `c.ativo` (a linha tem `active`) e `c.salarioBase` (a linha tem `baseSalary`). Resultado: **Ativos = 0**, **Inativos = todos**, **Folha salarial e Média salarial = NaN**. |
| B3 | **Alta** | `src/pages/Employees/EmployeesDash.jsx:167` | `mediaPorCargo = rows / totalRoles` divide um **array** por um número, o que dá sempre `NaN`. Com a lista vazia, `mediaSalarial` também divide por zero. |
| B4 | **Alta** | `src/pages/Employees/EmployeesDash.jsx:145,152` | O `id` vem do índice e não do backend, o que quebra edição e exclusão futuras. O campo é lido como `emp.isActive`, mas o cadastro envia `active`: contrato inconsistente com a API. O erro da API é só logado no console, e a tela não tem estado de carregamento nem de erro. |
| B5 | **Alta** | `src/pages/Employees/Employees.jsx:21,79,199-201` | O campo `role` começa como `1` (número), as opções do select são strings ("Vendedor", "Gestor"…) e o reset volta para `''`. O backend recebe tipos diferentes conforme o caminho, e o select abre sem nenhuma opção válida selecionada. |
| B6 | **Alta** | `src/pages/Settings/Settings.jsx:61-65` | O componente `IconTheme` usa arrow function com `{}` sem `return`, então **o ícone de tema nunca aparece**. Também é recriado a cada render (erro `react-hooks/static-components`). |
| B7 | **Média** | `src/service/api.js:10-15` | `...options` é espalhado **depois** de `headers`. Se a chamada passar `options.headers` (por exemplo, `Authorization`), o objeto inteiro é substituído e o `Content-Type: application/json` se perde. |
| B8 | **Média** | `src/service/api.js:2-6` | Faz `console.log` da URL da API em produção e lança erro **no import do módulo** quando falta `VITE_API_URL`. Como as páginas são importadas de forma estática em `main.jsx`, a falta da variável derruba o app inteiro, inclusive o Login. Não existe `.env.example`. |
| B9 | **Média** | `src/components/SideBar/SwipeableDrawer.jsx:65` | O logout chama `localStorage.clear()`, o que apaga também as preferências de tema e idioma do usuário. |
| B10 | **Média** | `AppLayout.jsx:33`, `SwipeableDrawer.jsx:76`, `Header.jsx:50` | As larguras não batem entre si: a sidebar tem 80/200 px, a margem do conteúdo 80/**240** px e o recuo do logo 65/190 px. Com o menu expandido sobra uma faixa de 40 px. |
| B11 | **Média** | `src/pages/Employees/EmployeesDash.jsx:279` | `Card` com `width: 2000` fixo causa scroll horizontal em qualquer tela menor. Também há `<Grid item>` fora de `<Grid container>` (linha 187; o mesmo acontece em `StockDash.jsx:53`). |
| B12 | **Média** | `src/components/Chart/ChartCard.jsx:24-37` | Faltam `key` nos `map`. Uma `<Line dataKey="value2">` fixa é sempre renderizada, mesmo quando não foi pedida. Todas as linhas usam a mesma cor. |
| B13 | Baixa | `ChartColumn.jsx`, `DonutChart.jsx`, `ChartIndicators.jsx`, `StatCard.jsx` | `type="monotone"` não se aplica a `<Bar>`. O id de gradiente `barGradient` é global e colide se houver dois gráficos na mesma tela. O tooltip tem fundo escuro fixo e ignora o tema claro. `ChartIndicators` divide por zero quando o total é 0. `variant="subtitle"` não existe no MUI. |
| B14 | Baixa | `src/pages/Employees/Employees.jsx:93,194,148` | Erro de digitação em `background.defaut`, `fullWidth={200}` (é booleano) e `rows={3}` num campo que não é `multiline`. |
| B15 | Baixa | Textos | "Despezas" (`Financial.jsx:195`), "Entre no NO" (`Login.jsx:20`). "Média de saídas/entradas" aparece com `%`, mas não é percentual (`StockDash.jsx:117,131`). "Total de produtos" soma unidades em estoque, não produtos. |

### 2.2 Segurança e arquitetura

- **Não há autenticação nem rota protegida.** Qualquer pessoa acessa `/app/*` digitando a URL. Os contextos se chamam `AuthLanguageProvider` e `AuthThemeProvider`, mas não têm relação com autenticação: o nome engana.
- **Dados de negócio mockados dentro dos componentes** (`Dashboard`, `Financial`, `StockDash`, `EmployeesDash`). Não existe uma camada de dados (cache, loading, erro, retry).
- **Código morto:** `src/components/MainContent/MainContent.jsx` importa `../SideBar/SideBar`, que não existe (quebra se alguém importar o arquivo). Também sobram `colaboradoresMock` sem uso, um bloco comentado inteiro em `ChartIndicators.jsx` e a prop `title` passada ao `DonutChart`, que a ignora.
- **`console.log` espalhados** em código de produção (`api.js`, `Employees.jsx`, `EmployeesDash.jsx`, `Stock.jsx`).

### 2.3 Consistência e qualidade de código

- **i18n incompleto:** existe infraestrutura de tradução, mas só Dashboard, Sidebar, Settings e o título do Stock a usam. `Employees`, `EmployeesDash`, `StockDash`, `Financial`, `Login`, `HeaderLogin` e `Header` têm textos fixos em português. As chaves `pages.employees.*` e `header.logoAlt` existem e não são usadas. O `index.html` está com `lang="en"`.
- **Formatação monetária manual** (`` `R$ ${valor}` ``), sem `Intl.NumberFormat`: não há separador de milhar nem respeito ao idioma.
- **Três abordagens de estilo misturadas:** CSS Modules, `sx` e `<input>` HTML puro (o formulário de Estoque não usa MUI, o de Colaboradores usa). O mesmo bloco de `sx` do `StatCard` está copiado seis vezes por página.
- **Reset CSS duplicado** (`App.css` + `CssBaseline`) com `outline: none` em botões e inputs. Isso remove o foco visível e é um problema de acessibilidade. A fonte é carregada via `@import` do Google Fonts no CSS, o que bloqueia a renderização.
- **Nomes inconsistentes:**
  - Pastas: `SideBar/SwipeableDrawer.jsx` exporta `Sidebar`, `Chart/ChartCard.jsx` exporta `Chart` (e não renderiza um Card), `chartcolors/` está em minúsculas e `service/` está no singular.
  - Dados com campos em português e inglês misturados (`nome`/`valor`/`percentual` × `name`/`value`).
  - Aspas e ponto-e-vírgula variam de arquivo para arquivo, porque não há Prettier.
- **Lint quebrado:** 6 erros e 1 aviso no ESLint (`no-undef`, `react-hooks/immutability`, `react-hooks/static-components`, `no-unused-vars`, `react-refresh/only-export-components`).

### 2.4 Infraestrutura e DX

- Sem **testes**, sem **CI**, sem **Prettier**, sem hooks de pre-commit e sem `.env.example`.
- `package.json` tem `"name": "package.json"` e `"version": "0.0.0"`, e não define `engines`. O README diz "Gestao de Empresas" em vez de NexOrder e cita Node 22.12/20.19 sem `.nvmrc`.
- **Bundle único de 1,46 MB** (448 KB gzip): MUI, DataGrid e Recharts são carregados até na tela de Login. Falta code-splitting por rota.
- A rota curinga `*` redireciona para o Login em vez de mostrar uma página 404.
- `package-lock.json` está com alterações não commitadas na `develop` (atualização de dependências transitivas). Decidir se entra em commit próprio ou se é descartado.

---

## 3. Melhorias sugeridas (visão do PO)

1. **Estabilizar antes de crescer.** Corrigir os bugs de severidade alta: hoje os indicadores de Colaboradores mostram números errados para o usuário, e um clique no Dashboard quebra a tela.
2. **Migrar para TypeScript cedo.** A base é pequena (cerca de 30 arquivos), então a migração é barata agora e fica cara depois. Os bugs B2 a B5 teriam sido pegos pelo compilador.
3. **Fundação de qualidade:** Prettier, ESLint sem erros, Vitest, CI no GitHub Actions bloqueando PRs para a `develop`.
4. **Autenticação real + rotas protegidas** antes de integrar os outros módulos à API.
5. **Camada de dados** com TanStack Query e formulários com `react-hook-form` + `zod`. Os schemas `zod` geram os tipos TS e validam os formulários.
6. **Substituir mocks pela API módulo a módulo:** Colaboradores → Estoque → Financeiro → Dashboard.
7. **Experiência do usuário:**
   - i18n completo, com moeda, números e datas via `Intl`.
   - Code-splitting por rota.
   - Acessibilidade (foco, `alt`, `aria-label`).
   - Estados de carregamento, vazio e erro.
   - Página 404.
   - Destaque da rota ativa no menu.

---

## 4. Plano de migração JavaScript → TypeScript

A migração é **incremental**, com `allowJs` ligado enquanto durar, para que o app nunca pare de funcionar. Cada etapa é um PR.

| Etapa | Entrega | Detalhes |
|-------|---------|----------|
| **T1. Setup** | Toolchain TS | Instalar `typescript` e `typescript-eslint`. Criar `tsconfig.json`, `tsconfig.app.json` e `tsconfig.node.json` (modelo do template `react-ts` do Vite) com `allowJs: true` e `strict: true`. Criar `src/vite-env.d.ts` tipando `ImportMetaEnv.VITE_API_URL`. Converter `vite.config.js` e `eslint.config.js` para `.ts`. Adicionar o script `"typecheck": "tsc -b --noEmit"`. |
| **T2. Domínio** | `src/types/` | `Employee`, `CreateEmployeeDTO`, `Role` (alinhado com o backend), `Product`, `StockMovement`, `FinancialTransaction`, `ApiError`. |
| **T3. Serviços** | `api.ts`, `employeeService.ts` | `apiFetch<T>()` genérico, classe `ApiError` com status e corpo, correção da mesclagem de headers (B7). |
| **T4. i18n e contextos** | `translations.ts`, `useI18n.ts`, providers | `translations` declarado com `as const satisfies`. O tipo `TranslationKey` é derivado das chaves, então `t('chave.inexistente')` passa a dar erro de compilação. Renomear os providers para `PreferencesProvider`. |
| **T5. Componentes** | `src/components/**/*.tsx` | Uma interface de props por componente. `Icon` com `name: IconName` (união das chaves). |
| **T6. Páginas e rotas** | `src/pages/**`, `layouts`, `main.tsx` | Converter as páginas e o roteador e atualizar `index.html` para `main.tsx`. |
| **T7. Endurecimento** | `strict` total | Remover `allowJs`. Ativar `noUncheckedIndexedAccess` e `noImplicitOverride`. Lint bloqueando novos `.js`/`.jsx` em `src/`. Atualizar o README. |

**Critério de pronto da migração:** `npm run typecheck`, `npm run lint`, `npm test` e `npm run build` verdes no CI, e nenhum arquivo `.js`/`.jsx` em `src/`.

---

## 5. Plano de ação (roadmap)

Os milestones correspondem a sprints. Prioridades: **P0** bloqueia o uso ou mostra dado errado, **P1** é fundação ou entrega de valor, **P2** é melhoria.

### Sprint 0 — Estabilização (P0)
- Corrigir PopularList/seleção no Dashboard (B1)
- Corrigir indicadores e mapeamento de Colaboradores (B2, B3, B4)
- Corrigir o campo Cargo do cadastro (B5, B14)
- Corrigir o ícone em Configurações (B6)
- Corrigir `apiFetch` e as variáveis de ambiente (B7, B8)
- Logout preservando preferências (B9)
- Alinhar larguras do layout e remover overflow (B10, B11)
- Corrigir componentes de gráfico (B12, B13)
- Corrigir textos e rótulos (B15)
- Zerar erros de lint e remover código morto

### Sprint 1 — Fundação (P1)
- Tooling: Prettier, EditorConfig, husky + lint-staged, metadados do `package.json`, `.nvmrc`, README
- CI no GitHub Actions
- Vitest + Testing Library
- **Épico de migração para TypeScript (T1 a T7)**
- Reorganizar pastas e convenções de nomes
- Centralizar tema/design tokens e corrigir reset CSS e acessibilidade de foco
- Extrair mocks e componentes repetidos

### Sprint 2 — Autenticação e integração (P1)
- Login real e AuthContext
- Rotas protegidas e tratamento de 401
- TanStack Query + tratamento global de erros
- `react-hook-form` + `zod`
- Colaboradores CRUD completo
- Estoque integrado
- Financeiro integrado
- Dashboard integrado

### Sprint 3 — UX, i18n e performance (P2)
- i18n completo + `Intl`
- Code-splitting
- Acessibilidade
- Estados de carregamento, vazio e erro + 404
- Menu de perfil e links do login

---

## 6. Como criar as tarefas no GitHub Projects

Pré-requisitos: [GitHub CLI](https://cli.github.com/) 2.42 ou superior, autenticado com escopo de projects.

```bash
gh auth login
gh auth refresh -s project,read:project

# Simular (não cria nada):
DRY_RUN=1 bash scripts/github-project-setup.sh

# Criar labels, milestones, projeto e issues:
bash scripts/github-project-setup.sh

# Usar um projeto que já existe (número na URL do projeto):
PROJECT_NUMBER=3 bash scripts/github-project-setup.sh
```

No Windows, rode no **Git Bash**. O script é idempotente: labels são atualizadas, e milestones e issues que já existem (mesmo título) não são duplicados.
