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
