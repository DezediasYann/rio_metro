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
