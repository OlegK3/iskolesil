/// Монохромный стиль MapLibre для схемы OpenMapTiles (слои Planetiler/OMT).
/// Все цвета — оттенки серого. Ресурсы только локальные (127.0.0.1).
/// Спрайтов нет: иконки POI не рисуются.
Map<String, dynamic> buildMonoStyle({
  required int port,
  required bool hasTiles,
  int maxZoom = 14,
}) {
  const bg = '#F5F5F5';
  const water = '#E2E2E2';
  const park = '#ECECEC';
  const landuse = '#F0F0F0';
  const building = '#E6E6E6';
  const road = '#CCCCCC'; // «непройденные улицы» из палитры
  const roadMajor = '#BEBEBE';
  const text = '#6E6E6E';

  final layers = <Map<String, dynamic>>[
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': bg},
    },
  ];

  if (hasTiles) {
    Map<String, dynamic> line(String id, List filter, String color,
            List<dynamic> width,
            {String? dash, double? minzoom}) =>
        {
          'id': id,
          'type': 'line',
          'source': 'omt',
          'source-layer': 'transportation',
          if (minzoom != null) 'minzoom': minzoom,
          'filter': filter,
          'layout': {'line-cap': 'round', 'line-join': 'round'},
          'paint': {
            'line-color': color,
            'line-width': width,
            if (dash != null) 'line-dasharray': [2, 2],
          },
        };

    List<dynamic> w(double a, double b, double c) => [
          'interpolate',
          ['exponential', 1.4],
          ['zoom'],
          10,
          a,
          14,
          b,
          18,
          c
        ];

    layers.addAll([
      {
        'id': 'landcover',
        'type': 'fill',
        'source': 'omt',
        'source-layer': 'landcover',
        'paint': {'fill-color': park, 'fill-opacity': 0.6},
      },
      {
        'id': 'landuse',
        'type': 'fill',
        'source': 'omt',
        'source-layer': 'landuse',
        'filter': [
          'in',
          'class',
          'residential',
          'commercial',
          'industrial',
          'cemetery',
          'playground',
          'school',
          'hospital'
        ],
        'paint': {'fill-color': landuse},
      },
      {
        'id': 'park',
        'type': 'fill',
        'source': 'omt',
        'source-layer': 'park',
        'paint': {'fill-color': park},
      },
      {
        'id': 'water',
        'type': 'fill',
        'source': 'omt',
        'source-layer': 'water',
        'paint': {'fill-color': water},
      },
      {
        'id': 'waterway',
        'type': 'line',
        'source': 'omt',
        'source-layer': 'waterway',
        'paint': {'line-color': water, 'line-width': 1.2},
      },
      {
        'id': 'building',
        'type': 'fill',
        'source': 'omt',
        'source-layer': 'building',
        'minzoom': 13,
        'paint': {'fill-color': building},
      },
      line(
          'road-path',
          [
            'in',
            'class',
            'path',
            'track',
          ],
          road,
          [
            'interpolate',
            ['linear'],
            ['zoom'],
            13,
            0.4,
            18,
            1.6
          ],
          dash: 'dash',
          minzoom: 13),
      line(
          'road-minor',
          [
            'in',
            'class',
            'minor',
            'service'
          ],
          road,
          w(0.4, 1.4, 6),
          minzoom: 12),
      line(
          'road-secondary',
          [
            'in',
            'class',
            'secondary',
            'tertiary'
          ],
          road,
          w(0.8, 2.2, 9)),
      line(
          'road-primary',
          [
            'in',
            'class',
            'primary',
            'trunk'
          ],
          roadMajor,
          w(1.0, 2.8, 11)),
      line(
          'road-motorway',
          [
            '==',
            'class',
            'motorway'
          ],
          roadMajor,
          w(1.2, 3.2, 12)),
      line(
          'rail',
          [
            '==',
            'class',
            'rail'
          ],
          '#C4C4C4',
          [
            'interpolate',
            ['linear'],
            ['zoom'],
            10,
            0.5,
            18,
            1.5
          ],
          dash: 'dash',
          minzoom: 10),
      {
        'id': 'road-labels',
        'type': 'symbol',
        'source': 'omt',
        'source-layer': 'transportation_name',
        'minzoom': 14,
        'layout': {
          'symbol-placement': 'line',
          'text-field': [
            'coalesce',
            ['get', 'name:ru'],
            ['get', 'name']
          ],
          'text-font': ['NotoSans-Regular'],
          'text-size': 11,
        },
        'paint': {
          'text-color': text,
          'text-halo-color': bg,
          'text-halo-width': 1.5,
        },
      },
      {
        'id': 'place-labels',
        'type': 'symbol',
        'source': 'omt',
        'source-layer': 'place',
        'filter': [
          'in',
          'class',
          'city',
          'town',
          'village',
          'suburb',
          'neighbourhood'
        ],
        'layout': {
          'text-field': [
            'coalesce',
            ['get', 'name:ru'],
            ['get', 'name']
          ],
          'text-font': ['NotoSans-Bold'],
          'text-size': [
            'match',
            ['get', 'class'],
            'city',
            18,
            'town',
            15,
            'village',
            13,
            11
          ],
        },
        'paint': {
          'text-color': '#4A4A4A',
          'text-halo-color': bg,
          'text-halo-width': 1.6,
        },
      },
    ]);
  }

  return {
    'version': 8,
    'name': 'iskolesil-mono',
    'glyphs': 'http://127.0.0.1:$port/fonts/{fontstack}/{range}.pbf',
    'sources': {
      if (hasTiles)
        'omt': {
          'type': 'vector',
          'tiles': ['http://127.0.0.1:$port/tiles/{z}/{x}/{y}.pbf'],
          'minzoom': 0,
          'maxzoom': maxZoom,
          'attribution': '© OpenStreetMap contributors, OpenMapTiles',
        },
    },
    'layers': layers,
  };
}
