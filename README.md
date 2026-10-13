# Patch Rio Metro para Subway Builder 1.7.2

Este patch destrava o mapa do Rio de Janeiro para rodar no Subway Builder **1.7.2** (que é a versão que corrige o lag da 1.7.0/1.7.1).

## O que mudou

### Diagnóstico

| Item | Antes | Depois |
|---|---|---|
| `manifest.json` | `>=1.7.0 <1.7.2` (bloqueia 1.7.2) | `>=1.7.0 <1.8.0` (libera 1.7.2 e 1.7.3) |
| `mod/index.js` | Sem proteção; qualquer erro de API derruba o mod inteiro | Cada chamada da API envolvida em try/catch; um erro não derruba o resto |
| `menu_mod/index.js` | Mesmo problema + chamada a `api.gameState.getMapColors()` que **não é API pública** | Mantida com fallback de cor hardcoded caso `getMapColors` desapareça em versões futuras |

### Por que isso funciona

Li o [changelog oficial](https://www.subwaybuilder.com/changelog) da 1.7.2 e a [documentação da Modding API](https://www.subwaybuilder.com/docs/api-reference/cities). Nenhuma das APIs usadas por este mapa foi removida ou renomeada entre 1.7.0 → 1.7.2:

- `api.registerCity` ✅
- `api.cities.registerTab` ✅
- `api.cities.setCityDataFiles` ✅
- `api.map.setTileURLOverride` ✅
- `api.map.setDefaultLayerVisibility` ✅
- `api.map.registerSource` ✅
- `api.map.registerLayer` ✅
- `api.hooks.onMapReady` ✅
- `api.hooks.onCityLoad` ✅
- `api.utils.getCityCode` ✅
- `api.ui.getResolvedTheme` ✅
- `api.gameState.getMapColors` ⚠️ não documentada — mantida com fallback

O único motivo do mapa não funcionar na 1.7.2 era o gate de versão no `manifest.json`. O resto do patch é blindagem.

### Sobre o lag da 1.7.0

A 1.7.2 corrige explicitamente (citação do changelog):

> **Improvement** — Got rid of 15 minute lag spikes by spreading out commuter decision calculations over several minutes.

Ou seja: rodar o Rio na 1.7.2 vai resolver tanto o "mapa não carrega" quanto o "mapa trava".

---

## Como aplicar no seu fork

### Passo 1 — Faça o fork no GitHub

1. Vá no repositório original do mapa do Rio (de onde você baixou este zip).
2. Clique em **Fork** no canto superior direito.
3. Marque "Copy the main branch only".

### Passo 2 — Abra no Codespace

1. No seu fork, clique no botão verde **Code** → aba **Codespaces**.
2. Clique em **Create codespace on main**.
3. Aguarde o VS Code carregar no navegador.

### Passo 3 — Substitua os 3 arquivos

Você vai sobrepor estes arquivos no repo:

| Arquivo no repo | Substituir pelo |
|---|---|
| `manifest.json` | `manifest.json` desta pasta |
| `mod/index.js` | `mod_index.js` desta pasta (renomeie para `index.js` ao salvar) |
| `menu_mod/index.js` | `menu_mod_index.js` desta pasta (renomeie para `index.js` ao salvar) |

#### No Codespace (VS Code web):

1. No painel Explorer (esquerda), abra `manifest.json`.
2. Apague tudo (`Ctrl+A` → `Delete`).
3. Abra o arquivo `manifest.json` que está nesta pasta (você pode abri-lo localmente no seu computador, copiar o conteúdo e colar no Codespace).
4. Salve (`Ctrl+S`).
5. Repita para `mod/index.js` (use `mod_index.js`) e `menu_mod/index.js` (use `menu_mod_index.js`).

> **Dica:** Para evitar confusão com os nomes temporários, abra os arquivos `mod_index.js` e `menu_mod_index.js` localmente, copie o conteúdo, e cole sobre o `index.js` correspondente dentro da pasta `mod/` e `menu_mod/` no Codespace. Os nomes finais no repo devem continuar sendo `index.js` — só o conteúdo muda.

### Passo 4 — Faça commit e push

No Codespace (VS Code):

1. Clique no ícone de Source Control na barra lateral esquerda (ou `Ctrl+Shift+G`).
2. Você verá os 3 arquivos modificados. Passe o mouse sobre cada um e clique em `+` para stagear.
3. Escreva uma mensagem tipo: `Libera compatibilidade com Subway Builder 1.7.2 e adiciona guards defensivos`.
4. Clique em **Commit**.
5. Clique em **Sync Changes** (ou rode `git push` no terminal).

### Passo 5 — (Opcional) Teste local antes de publicar

Se você tem o jogo instalado e o Python configurado:

```sh
# No codespace ou localmente
pip install -r requirements.txt
python serve_rio.py        # sobe servidor local na porta 8080
```

Aí no jogo:

1. Importe `dist/RIO.zip` pelo Railyard (menu de mods).
2. Habilite o mod.
3. Abra o console do browser com `F12`.
4. Selecione a cidade do Rio.
5. Acompanhe o console. Se algo falhar, vai aparecer mensagens tipo:
   ```
   [Rio] Falha em registerLayer rio-scenery-roads: ...
   ```
   Esses logs me dizem exatamente onde ajustar.

### Passo 6 — Publicar para o Railyard (opcional)

Se quiser subir como release no GitHub para outras pessoas baixarem:

```sh
python build_rio.py --package-only
```

Isso gera `dist/RIO.zip` com o `manifest.json` novo já embutido. Aí você cria uma release `v2.2.1` no GitHub e faz upload de:

- `dist/RIO.zip`
- `dist/manifest.json` (solto, como asset separado)

> ⚠️ Atenção: eu **não rodei** `build_rio.py` porque ele depende de tippecanoe, fontes do IBGE, e vários passos de build que demoram. O patch foi feito **diretamente sobre os arquivos JS e o manifest** — que é tudo que o jogo lê em runtime.

---

## O que pode dar errado (e como diagnosticar)

Se o mapa não carregar mesmo após o patch, abra o console do jogo (`F12`) e procure por:

### Erro 1: `[Rio] SubwayBuilderAPI indisponível`

O mod nem encontrou a API. Provável que o `manifest.json` do mod (`mod/manifest.json`) esteja errado, ou o mod não está habilitado no Railyard.

### Erro 2: `[Rio] Falha em registerCity: ...`

A API mudou a assinatura de `registerCity`. Provável que a 1.7.2 ou uma futura 1.7.3 exigiu um campo novo. Me manda a mensagem de erro exata que eu ajusto.

### Erro 3: mapa carrega mas falta água / rios

Olhe se aparece `[Rio] addLayer falhou para rio-waterways: ...`. Pode ser que o source-layer `waterways` foi renomeado no tileset. Aí é preciso regerar o tiles ou trocar o nome.

### Erro 4: mapa carrega mas cidade não aparece na lista

Provável que o `api.cities.registerTab` mudou ou que há um conflito de city code. Veja se o console tem `[Modding API] City registered: RIO`. Se não tem, o `registerCity` não rodou.

### Erro 5: `getMapColors is not a function`

Isso é esperado em algumas versões — o código já tem fallback pra cor hardcoded, então **não deve quebrar nada**, mas pode aparecer um warn. Se apareceu, é só ignorar.

---

## Estrutura dos arquivos no repo

```
rio_metro-master/
├── manifest.json             ← ALTERAR (root)
├── mod/
│   ├── manifest.json         ← não mexer
│   └── index.js              ← ALTERAR
├── menu_mod/
│   ├── manifest.json         ← não mexer
│   └── index.js              ← ALTERAR
└── ... (scripts Python de build — não mexer)
```

---

## Diferenças chave vs. versão original

### `manifest.json`

```diff
- "subway-builder": ">=1.7.0 <1.7.2"
+ "subway-builder": ">=1.7.0 <1.8.0"
```

### `mod/index.js`

- Adicionado `'use strict'`
- Adicionado guard `window.__rioCityRegistered` (evita double-register em hot-reload)
- Cada chamada da API envolta em `safe('nome', function(){...})` com try/catch
- Helper `safe()` loga erros com prefixo `[Rio]` no console

### `menu_mod/index.js`

- Adicionado `'use strict'`
- Reescrito em 3 blocos isolados (cada IIFE protege o outro)
- `getMapColors()` envolto em try/catch com fallback pra objeto vazio
- `getResolvedTheme()` envolto em try/catch
- `map.on/off`, `map.getLayer`, `map.addLayer` todos guardados
- Logs com prefixo `[Rio]` em todos os warns

---

## Depois que funcionar

Me conta como foi e a gente decide se:

1. **Manda um PR pro repositório original** do mapa do Rio (com os créditos ao autor original) — útil pra outros usuários que sofrem com o mesmo problema.
2. **Publica como fork separado** no seu GitHub (mais rápido, mas fragmenta a comunidade).
3. **Só usa localmente** (se for só pra você).

Qualquer um dos caminhos, o patch aqui já está pronto. Basta aplicar.
