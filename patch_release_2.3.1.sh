set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f "manifest.json" || ! -d "mod" || ! -d "menu_mod" ]]; then
  echo "ERRO: rode este script de dentro da raiz do repo rio_metro."
  exit 1
fi

RIO_FORK="${RIO_FORK:-}"
if [[ -z "$RIO_FORK" ]]; then
  # Tenta auto-detectar do remote origin
  REMOTE_URL="$(git remote get-url origin 2>/dev/null || echo '')"
  if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+/rio_metro) ]]; then
    RIO_FORK="${BASH_REMATCH[1]}"
  else
    echo "ERRO: não consegui detectar seu fork. Rode com:"
    echo "  RIO_FORK=SeuUsuario/rio_metro bash patch_release_2.3.1.sh"
    exit 1
  fi
fi
echo "==> Fork detectado: $RIO_FORK"

echo "==> Patcheando repo para versão 2.3.1 (otimizações de performance)..."

# ─── 1. manifest.json (raiz) — faixa mantida ───────────────────────────────
cat > manifest.json <<'JSON'
{
  "dependencies": {
    "subway-builder": ">=1.7.0 <1.8.0"
  }
}
JSON
echo "  ✓ manifest.json (raiz) — faixa >=1.7.0 <1.8.0"

# ─── 2. mod/index.js — versão 2.3.1 com modifyConstants + modifyPathfindingRules ──
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
                zoom: 11.0,            // era 10.5 — começa mais próximo pra carregar menos tiles no startup
                latitude: -22.92,     // centralizado na zona sul + centro + Niterói (região com mais demanda)
                longitude: -43.20,
                bearing: 0
            },
            minZoom: 9,                // era 8 — impede zoom-out que carrega toda a área metropolitana
            buildingZoomOffset: 0.5,  // era -0.75 — prédios só aparecem mais zoomed-in (alívio grande na GPU)
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

    // ─── Otimizações de simulação (aplicadas quando a cidade do Rio carrega) ─────
    function applyRioOptimizations() {
        safe('modifyPathfindingRules', function () {
            if (typeof api.modifyPathfindingRules !== 'function') return;
            api.modifyPathfindingRules({
                MAX_TRANSFERS: 3,                  // era 4 — menos combinações exploradas por pop
                MAX_WALK_TO_FROM_STATION: 1800,    // era 2700 (45min) → 30min
                MAX_TRANSFER_WALKING_TIME: 480,   // era 600
                MAX_RANGE_DEPARTURES: 16           // era 24
            });
        });
        safe('modifyConstants', function () {
            if (typeof api.modifyConstants !== 'function') return;
            api.modifyConstants({
                COMMUTE_INTERVAL_LENGTH: 600,
                TICKS_PER_UPDATE: {
                    ultrafast: { gameState: 12, trainCoords: 12, popMovement: 12, popMovementGeojson: 24 },
                    fast:      { gameState: 16, trainCoords: 16, popMovement: 16, popMovementGeojson: 32 }
                }
            });
        });
    }

    safe('onCityLoad applyRioOptimizations', function () {
        if (!api.hooks || typeof api.hooks.onCityLoad !== 'function') return;
        api.hooks.onCityLoad(function (cityCode) {
            const code = String(cityCode || '').split(':').pop();
            if (code === 'RIO') {
                applyRioOptimizations();
                console.log('[Rio] Otimizações de performance 2.3.1 aplicadas.');
            }
        });
    });

    try {
        if (api.utils && typeof api.utils.getCityCode === 'function') {
            if (String(api.utils.getCityCode() || '').split(':').pop() === 'RIO') {
                applyRioOptimizations();
            }
        }
    } catch (e) { /* ignore */ }

    console.log('[Rio] Censo 2022, mapa ampliado, profundidades e otimizações 2.3.1 carregados.');
})();
JS
echo "  ✓ mod/index.js (2.3.1 — com modifyConstants/PathfindingRules)"

# ─── 3. menu_mod/index.js — mantém 2.3.0 (defensivo, sem mudanças) ─────────
# Só reescreve se não estiver no formato esperado (pra garantir consistência).
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
        catch (e) { /* getMapColors não é API pública; fallback */ }

        const water = colors.water || (dark ? '#294d60' : '#91bccf');
        const layers = [
            { id: 'rio-waterways', type: 'line', source: 'general-tiles', 'source-layer': 'waterways', minzoom: 8,
              paint: { 'line-color': water, 'line-width': ['interpolate', ['linear'], ['zoom'], 8, 0.5, 12, 1.2, 16, 2.2] } },
            { id: 'rio-coastline', type: 'line', source: 'general-tiles', 'source-layer': 'coastline',
              paint: { 'line-color': dark ? '#527888' : '#648e9f', 'line-width': ['interpolate', ['linear'], ['zoom'], 6, 0.3, 13, 0.7, 16, 1.1], 'line-opacity': 0.75 } },
            { id: 'rio-scenery-roads', type: 'line', source: 'general-tiles', 'source-layer': 'scenery_roads',
              paint: { 'line-color': dark ? '#69757a' : '#959e9f', 'line-width': ['interpolate', ['linear'], ['zoom'], 8, 0.3, 14, 1.2], 'line-opacity': 0.7 } }
        ];
        const before = ['buildings-3d', 'building-foundations'].find(function (id) {
            try { return map.getLayer(id); } catch (e) { return false; }
        });
        for (const layer of layers) {
            try { if (!map.getLayer(layer.id)) map.addLayer(layer, before); }
            catch (e) { console.warn('[Rio] addLayer falhou para ' + layer.id + ':', e && e.message || e); }
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
                try { if (activeMap && typeof activeMap.off === 'function') activeMap.off('styledata', schedule); }
                catch (e) { /* ignore */ }
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
echo "  ✓ menu_mod/index.js (mantido defensivo)"

# ─── 4. Bump de versão 2.3.0 → 2.3.1 ────────────────────────────────────────
python3 - <<'PY'
import json, pathlib, re
p = pathlib.Path("mod/manifest.json")
d = json.loads(p.read_text())
d["version"] = "2.3.1"
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
print("  ✓ mod/manifest.json version → 2.3.1")
PY

python3 - <<'PY'
import pathlib, re
p = pathlib.Path("map_settings.py")
t = p.read_text()
m = re.search(r"VERSION\s*=\s*'([^']+)'", t)
if not m:
    print("  ! map_settings.py: linha VERSION não encontrada")
else:
    old_v = m.group(1)
    if old_v == "2.3.1":
        print("  ✓ map_settings.py já está em 2.3.1")
    else:
        t2 = re.sub(r"VERSION\s*=\s*'[^']+'", "VERSION='2.3.1'", t)
        p.write_text(t2)
        print(f"  ✓ map_settings.py VERSION: {old_v} → 2.3.1")
PY

# ─── 5. Baixa RIO.zip da release v2.3.0 do SEU fork ───────────────────────
mkdir -p dist _tmp
if [[ ! -f _tmp/RIO-v2.3.0.zip ]]; then
  URL="https://github.com/${RIO_FORK}/releases/download/v2.3.0/RIO.zip"
  echo "  ↓ baixando RIO.zip da release v2.3.0 do ${RIO_FORK}..."
  echo "    URL: $URL"
  if ! curl -sSL -o _tmp/RIO-v2.3.0.zip "$URL"; then
    echo "  ! não consegui baixar. Verifique se a release v2.3.0 existe no seu fork."
    exit 2
  fi
  if [[ ! -s _tmp/RIO-v2.3.0.zip ]]; then
    echo "  ! arquivo baixado está vazio. URL pode estar errada."
    exit 2
  fi
fi

# ─── 6. Reempacota RIO.zip com config.json alterado (zoom, lat/lon, buildingZoomOffset) ──
echo "  → reempacotando config.json interno para 2.3.1..."
python3 - <<'PY'
import json, zipfile, pathlib
src = pathlib.Path("_tmp/RIO-v2.3.0.zip")
dst = pathlib.Path("dist/RIO.zip")
dst.parent.mkdir(parents=True, exist_ok=True)

with zipfile.ZipFile(src) as zin:
    names = zin.namelist()
    cfg = json.loads(zin.read("config.json"))
    old_v = cfg.get("version")
    old_zoom = cfg.get("initialViewState", {}).get("zoom")
    old_lat = cfg.get("initialViewState", {}).get("latitude")
    old_lon = cfg.get("initialViewState", {}).get("longitude")
    old_minzoom = cfg.get("minZoom")
    old_bzo = cfg.get("buildingZoomOffset")

    cfg["version"] = "2.3.1"
    # Aplica os mesmos valores que o mod/index.js — espelha config.json dentro do zip,
    # porque o Railyard às vezes lê config.json antes de rodar o mod.
    cfg["initialViewState"] = {
        "zoom": 11.0,
        "latitude": -22.92,
        "longitude": -43.20,
        "bearing": 0
    }
    cfg["minZoom"] = 9
    cfg["buildingZoomOffset"] = 0.5

    cfg_bytes_new = json.dumps(cfg, ensure_ascii=False, separators=(",", ":")).encode()

    with zipfile.ZipFile(dst, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zout:
        for name in names:
            data = zin.read(name)
            if name == "config.json":
                data = cfg_bytes_new
            zout.writestr(name, data)

    print(f"  ✓ dist/RIO.zip gerado")
    print(f"    version:           {old_v} → 2.3.1")
    print(f"    initialZoom:       {old_zoom} → 11.0")
    print(f"    initialLat:        {old_lat} → -22.92")
    print(f"    initialLon:        {old_lon} → -43.20")
    print(f"    minZoom:           {old_minzoom} → 9")
    print(f"    buildingZoomOffset:{old_bzo} → 0.5")
PY

# ─── 7. Cópia do manifest.json (raiz) para dist/ ──────────────────────────
cp manifest.json dist/manifest.json
echo "  ✓ dist/manifest.json (compat >=1.7.0 <1.8.0)"

rm -rf _tmp
