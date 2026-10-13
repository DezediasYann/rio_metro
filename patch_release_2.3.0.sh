#!/usr/bin/env bash
# patch_release_2.3.0.sh
# Roda no codespace do fork do rio_metro.
# Faz:
#   1. Aplica os patches nos 3 arquivos (manifest.json raiz, mod/index.js, menu_mod/index.js)
#   2. Bumpa versão 2.2.0 → 2.3.0 em mod/manifest.json e map_settings.py
#   3. Baixa o RIO.zip da release v2.2.0 do repo original
#   4. Reempacota com config.json atualizado pra 2.3.0
#   5. Coloca tudo em dist/ pronto pra criar a release v2.3.0 no GitHub
#
# Uso:
#   cd /workspaces/rio_metro  (ou onde seu codespace montou o repo)
#   bash patch_release_2.3.0.sh

set -euo pipefail

# ─── Detecta o ROOT do repo ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f "manifest.json" || ! -d "mod" || ! -d "menu_mod" ]]; then
  echo "ERRO: rode este script de dentro da raiz do repo rio_metro."
  echo "Arquivos esperados: manifest.json, mod/, menu_mod/"
  exit 1
fi

echo "==> Patcheando repo para versão 2.3.0 + compat 1.7.2..."

# ─── 1. manifest.json (raiz) — faixa de compatibilidade ────────────────────
cat > manifest.json <<'JSON'
{
  "dependencies": {
    "subway-builder": ">=1.7.0 <1.8.0"
  }
}
JSON
echo "  ✓ manifest.json (raiz) — faixa >=1.7.0 <1.8.0"

# ─── 2. mod/index.js — versão defensiva com try/catch ──────────────────────
cat > mod/index.js <<'JS'
(function () {
    'use strict';

    const api = window.SubwayBuilderAPI;
    if (!api) {
        console.error('[Rio] SubwayBuilderAPI indisponível.');
        return;
    }
    if (window.__rioCityRegistered) {
        return;
    }
    window.__rioCityRegistered = true;

    function safe(label, fn) {
        try {
            fn();
        } catch (e) {
            console.error('[Rio] Falha em ' + label + ':', e && e.message || e);
        }
    }

    const base = 'http://127.0.0.1:8080';

    safe('registerCity', function () {
        api.registerCity({
            name: 'Rio de Janeiro',
            code: 'RIO',
            description: 'Build a rail network across Greater Rio, connecting Rio de Janeiro, the Baixada Fluminense, Niterói, São Gonçalo and the wider metropolitan area.',
            population: 11491836,
            initialViewState: {
                zoom: 10.5,
                latitude: -22.84,
                longitude: -43.3,
                bearing: 0
            },
            minZoom: 8,
            buildingZoomOffset: -0.75,
            mapImageUrl: base + '/RIO/thumbnail.png'
        });
    });

    safe('registerTab BR', function () {
        api.cities.registerTab({
            id: 'BR',
            label: 'BR',
            emoji: '🇧🇷',
            cityCodes: ['RIO']
        });
    });

    safe('setCityDataFiles', function () {
        api.cities.setCityDataFiles('RIO', {
            buildingsIndex: base + '/data/RIO/buildings_index.bin',
            demandData: base + '/data/RIO/demand_data.json',
            roads: base + '/data/RIO/roads.geojson',
            runwaysTaxiways: base + '/data/RIO/runways_taxiways.geojson',
            oceanDepthIndex: base + '/data/RIO/ocean_depth_index.json.gz'
        });
    });

    safe('setTileURLOverride', function () {
        api.map.setTileURLOverride({
            cityCode: 'RIO',
            tilesUrl: base + '/RIO/{z}/{x}/{y}.mvt',
            foundationTilesUrl: base + '/RIO_foundations/{z}/{x}/{y}.mvt',
            maxZoom: 15
        });
    });

    safe('setDefaultLayerVisibility', function () {
        api.map.setDefaultLayerVisibility('RIO', {
            buildingFoundations: true,
            oceanFoundations: false
        });
    });

    safe('registerSource rio-scenery', function () {
        api.map.registerSource('rio-scenery', {
            type: 'vector',
            tiles: [base + '/RIO/{z}/{x}/{y}.mvt'],
            minzoom: 6,
            maxzoom: 15,
            bounds: [-44.06, -23.24, -42.67, -22.40]
        });
    });

    safe('registerLayer rio-scenery-roads', function () {
        api.map.registerLayer({
            id: 'rio-scenery-roads',
            type: 'line',
            source: 'rio-scenery',
            'source-layer': 'scenery_roads',
            paint: {
                'line-color': '#8a9195',
                'line-width': ['interpolate', ['linear'], ['zoom'], 8, 0.35, 14, 1.6],
                'line-opacity': 0.65
            }
        });
    });

    safe('onMapReady setMaxBounds', function () {
        if (!api.hooks || typeof api.hooks.onMapReady !== 'function') return;
        api.hooks.onMapReady(function (map) {
            try {
                if (api.utils && typeof api.utils.getCityCode === 'function') {
                    if (api.utils.getCityCode() !== 'RIO') return;
                }
                if (map && typeof map.setMaxBounds === 'function') {
                    map.setMaxBounds([[-44.06, -23.24], [-42.67, -22.40]]);
                }
            } catch (e) {
                console.warn('[Rio] setMaxBounds falhou:', e && e.message || e);
            }
        });
    });

    console.log('[Rio] Censo 2022, mapa ampliado e profundidades carregados.');
})();
JS
echo "  ✓ mod/index.js (defensivo)"

# ─── 3. menu_mod/index.js — versão defensiva com fallbacks ─────────────────
cat > menu_mod/index.js <<'JS'
(function () {
    'use strict';

    const api = window.SubwayBuilderAPI;
    if (!api || window.__rioMenuInstalled) return;
    window.__rioMenuInstalled = true;

    try {
        const originalFetch = globalThis.fetch.bind(globalThis);
        globalThis.fetch = async function (input, init) {
            const response = await originalFetch(input, init);
            const url = typeof input === 'string' ? input : (input && input.url) || String(input);
            if (!/\/cityPopulations\.json(?:[?#]|$)/.test(url) || !response.ok) return response;
            try {
                const data = await response.clone().json();
                if (!Array.isArray(data)) return response;
                const rows = data.filter(function (c) { return c.code !== 'RIO'; });
                rows.push({ code: 'RIO', population: 11491836 });
                const headers = new Headers(response.headers);
                headers.delete('content-length');
                headers.delete('content-encoding');
                headers.set('content-type', 'application/json');
                return new Response(JSON.stringify(rows), { status: response.status, headers: headers });
            } catch (e) {
                console.warn('[Rio] não consegui reescrever cityPopulations.json:', e && e.message || e);
                return response;
            }
        };
    } catch (e) {
        console.warn('[Rio] fetch intercept falhou:', e && e.message || e);
    }

    try {
        if (api.cities && typeof api.cities.registerTab === 'function') {
            api.cities.registerTab({ id: 'BR', label: 'BR', emoji: '🇧🇷', cityCodes: ['RIO'] });
        }
        if (api.map && typeof api.map.setDefaultLayerVisibility === 'function') {
            api.map.setDefaultLayerVisibility('RIO', { oceanFoundations: false });
        }
    } catch (e) {
        console.warn('[Rio] registro de aba/layer falhou:', e && e.message || e);
    }
})();

(function () {
    'use strict';

    const api = window.SubwayBuilderAPI;
    if (!api || window.__rioSurfaceLayersInstalled) return;
    window.__rioSurfaceLayersInstalled = true;

    let activeMap = null;
    let pending = false;

    function update() {
        pending = false;
        const map = activeMap;
        if (!map) return;
        if (!api.utils || typeof api.utils.getCityCode !== 'function') return;

        const code = String(api.utils.getCityCode() || '').split(':').pop();
        if (code !== 'RIO') return;
        if (!map.getSource || !map.getLayer || !map.addLayer) return;
        if (!map.getSource('general-tiles')) return;

        let dark = false;
        try { dark = api.ui && typeof api.ui.getResolvedTheme === 'function' && api.ui.getResolvedTheme() === 'dark'; }
        catch (e) { /* ignore */ }

        let colors = {};
        try { colors = (api.gameState && typeof api.gameState.getMapColors === 'function') ? (api.gameState.getMapColors() || {}) : {}; }
        catch (e) { /* getMapColors não é API pública; cai no fallback */ }

        const water = colors.water || (dark ? '#294d60' : '#91bccf');
        const layers = [
            {
                id: 'rio-waterways', type: 'line', source: 'general-tiles', 'source-layer': 'waterways', minzoom: 8,
                paint: { 'line-color': water, 'line-width': ['interpolate', ['linear'], ['zoom'], 8, 0.5, 12, 1.2, 16, 2.2] }
            },
            {
                id: 'rio-coastline', type: 'line', source: 'general-tiles', 'source-layer': 'coastline',
                paint: { 'line-color': dark ? '#527888' : '#648e9f', 'line-width': ['interpolate', ['linear'], ['zoom'], 6, 0.3, 13, 0.7, 16, 1.1], 'line-opacity': 0.75 }
            },
            {
                id: 'rio-scenery-roads', type: 'line', source: 'general-tiles', 'source-layer': 'scenery_roads',
                paint: { 'line-color': dark ? '#69757a' : '#959e9f', 'line-width': ['interpolate', ['linear'], ['zoom'], 8, 0.3, 14, 1.2], 'line-opacity': 0.7 }
            }
        ];

        const before = ['buildings-3d', 'building-foundations'].find(function (id) {
            try { return map.getLayer(id); } catch (e) { return false; }
        });
        for (const layer of layers) {
            try {
                if (!map.getLayer(layer.id)) map.addLayer(layer, before);
            } catch (e) {
                console.warn('[Rio] addLayer falhou para ' + layer.id + ':', e && e.message || e);
            }
        }
    }

    function schedule() {
        if (pending) return;
        pending = true;
        setTimeout(update, 0);
    }

    try {
        if (api.hooks && typeof api.hooks.onMapReady === 'function') {
            api.hooks.onMapReady(function (map) {
                try {
                    if (activeMap && typeof activeMap.off === 'function') {
                        activeMap.off('styledata', schedule);
                    }
                } catch (e) { /* ignore */ }
                activeMap = map || (api.utils && typeof api.utils.getMap === 'function' ? api.utils.getMap() : null);
                if (!activeMap) return;
                if (typeof activeMap.on === 'function') activeMap.on('styledata', schedule);
                schedule();
            });
        }
        if (api.hooks && typeof api.hooks.onCityLoad === 'function') {
            api.hooks.onCityLoad(schedule);
        }
    } catch (e) {
        console.warn('[Rio] registro de hooks de superfície falhou:', e && e.message || e);
    }
})();
JS
echo "  ✓ menu_mod/index.js (defensivo)"

# ─── 4. Bump de versão 2.2.0 → 2.3.0 ───────────────────────────────────────
# mod/manifest.json
python3 - <<'PY'
import json, pathlib
p = pathlib.Path("mod/manifest.json")
d = json.loads(p.read_text())
d["version"] = "2.3.0"
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
print("  ✓ mod/manifest.json version → 2.3.0")
PY

# map_settings.py
if [[ -f map_settings.py ]]; then
  python3 - <<'PY'
import pathlib, re
p = pathlib.Path("map_settings.py")
t = p.read_text()
m = re.search(r"VERSION\s*=\s*'([^']+)'", t)
if not m:
    print("  ! map_settings.py: linha VERSION não encontrada; cheque o arquivo")
else:
    old_v = m.group(1)
    if old_v == "2.3.0":
        print("  ✓ map_settings.py já está em 2.3.0")
    else:
        t2 = re.sub(r"VERSION\s*=\s*'[^']+'", "VERSION='2.3.0'", t)
        p.write_text(t2)
        print(f"  ✓ map_settings.py VERSION: {old_v} → 2.3.0")
PY
fi

# ─── 5. Baixa RIO.zip da release v2.2.0 do repo original ──────────────────
mkdir -p dist _tmp
if [[ ! -f _tmp/RIO-v2.2.0.zip ]]; then
  echo "  ↓ baixando RIO.zip da release v2.2.0 do JGuylherme/rio_metro..."
  curl -sSL -o _tmp/RIO-v2.2.0.zip \
    "https://github.com/JGuylherme/rio_metro/releases/download/v2.2.0/RIO.zip"
  if [[ ! -s _tmp/RIO-v2.2.0.zip ]]; then
    echo "  ! não consegui baixar. Talvez a release esteja em outro repo."
    echo "    Tente informar a URL manualmente em RIO_ZIP_URL."
    exit 2
  fi
fi

# ─── 6. Reempacota RIO.zip com config.json apontando pra 2.3.0 ────────────
echo "  → reempacotando config.json interno para 2.3.0..."
python3 - <<'PY'
import json, zipfile, shutil, pathlib
src = pathlib.Path("_tmp/RIO-v2.2.0.zip")
dst = pathlib.Path("dist/RIO.zip")
dst.parent.mkdir(parents=True, exist_ok=True)

with zipfile.ZipFile(src) as zin:
    names = zin.namelist()
    cfg_bytes = zin.read("config.json")
    cfg = json.loads(cfg_bytes)
    old_v = cfg.get("version")
    cfg["version"] = "2.3.0"
    cfg_bytes_new = json.dumps(cfg, ensure_ascii=False, separators=(",", ":")).encode()

    with zipfile.ZipFile(dst, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zout:
        for name in names:
            data = zin.read(name)
            if name == "config.json":
                data = cfg_bytes_new
            zout.writestr(name, data)

print(f"  ✓ dist/RIO.zip gerado (config.version: {old_v} → 2.3.0)")
PY

# ─── 7. Cópia do manifest.json (raiz) para dist/ ──────────────────────────
cp manifest.json dist/manifest.json
echo "  ✓ dist/manifest.json (compat >=1.7.0 <1.8.0)"

# ─── 8. Limpa e mostra resumo ─────────────────────────────────────────────
rm -rf _tmp
echo
echo "==============================================="
echo "  Patch + reempacotamento concluídos."
echo "==============================================="
echo
echo "Arquivos prontos para release v2.3.0:"
echo "  dist/RIO.zip        (dados do mapa, com config.version=2.3.0)"
echo "  dist/manifest.json  (faixa >=1.7.0 <1.8.0)"
echo
echo "Próximos passos:"
echo "  1. Confira com:  git status --short"
echo "  2. Faça commit:  git add -A && git commit -m 'Release v2.3.0: 1.7.2 compat'"
echo "  3. Dê push:      git push"
echo "  4. Crie release v2.3.0 no GitHub, anexando:"
echo "       dist/RIO.zip"
echo "       dist/manifest.json"
