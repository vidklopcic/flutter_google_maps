// Copyright (c) 2020, the MarchDev Toolkit project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:html';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import 'package:uuid/uuid.dart';
import 'package:flinq/flinq.dart';
import 'package:google_maps/google_maps.dart';
import 'package:google_directions_api/google_directions_api.dart' show GeoCoord, GeoCoordBounds;

import 'utils.dart';
import '../core/google_map.dart';
import '../core/utils.dart' as utils;
import '../core/map_items.dart' as items;

class GoogleMapState extends GoogleMapStateBase {
  final htmlId = Uuid().v1();
  final directionsService = DirectionsService();

  final _markers = <String, Marker>{};
  final _infoState = <String, bool>{};
  final _infos = <String, InfoWindow>{};
  final _polygons = <String, Polygon>{};
  final _circles = <String, Circle>{};
  final _subscriptions = <StreamSubscription>[];
  final _directions = <String, DirectionsRenderer>{};

  GMap _map;
  MapOptions _mapOptions;

  String _getImage(String image) {
    if (image == null) return null;

    if (utils.ByteString.isByteString(image)) {
      final blob = Blob([utils.ByteString.fromString(image)], 'image/png');
      return Url.createObjectUrlFromBlob(blob);
    }

    return '${fixAssetPath(image)}assets/$image';
  }

  @override
  void moveCameraBounds(
    GeoCoordBounds newBounds, {
    double padding = 0,
    bool animated = true,
    bool waitUntilReady = true,
  }) {
    assert(() {
      if (newBounds == null) {
        throw ArgumentError.notNull('newBounds');
      }

      return true;
    }());

    _map.center = newBounds.center.toLatLng();

    final zoom = _map.zoom;
    if (animated == true) {
      _map.panToBounds(newBounds.toLatLngBounds());
    } else {
      _map.fitBounds(newBounds.toLatLngBounds());
    }
    _map.zoom = zoom;
  }

  @override
  void moveCamera(
    GeoCoord latLng, {
    bool animated = true,
    bool waitUntilReady = true,
    double zoom,
  }) {
    assert(() {
      if (latLng == null) {
        throw ArgumentError.notNull('latLng');
      }

      return true;
    }());

    if (animated == true) {
      _map.panTo(latLng.toLatLng());
      _map.zoom = zoom ?? _map.zoom;
    } else {
      _map.center = latLng.toLatLng();
      _map.zoom = zoom ?? _map.zoom;
    }
  }

  @override
  void zoomCamera(
    double zoom, {
    bool animated = true,
    bool waitUntilReady = true,
  }) {
    assert(() {
      if (zoom == null) {
        throw ArgumentError.notNull('zoom');
      }

      return true;
    }());

    _map.zoom = zoom;
  }

  @override
  FutureOr<GeoCoord> get center => _map.center?.toGeoCoord();

  @override
  void changeMapStyle(
    String mapStyle, {
    bool waitUntilReady = true,
  }) {
    try {
      _mapOptions.styles = mapStyle?.parseMapStyle();
      _map.options = _mapOptions;
    } catch (e) {
      throw utils.MapStyleException(e.toString());
    }
  }

  @override
  void addMarkerRaw(
    GeoCoord position, {
    String label,
    String icon,
    String info,
    String infoSnippet,
    ValueChanged<String> onTap,
    ui.VoidCallback onInfoWindowTap,
  }) {
    assert(() {
      if (position == null) {
        throw ArgumentError.notNull('position');
      }

      if (position.latitude == null || position.longitude == null) {
        throw ArgumentError.notNull('position.latitude && position.longitude');
      }

      return true;
    }());

    final key = position.toString();

    if (_markers.containsKey(key)) return;

    final marker = Marker()
      ..map = _map
      ..label = label
      ..icon = _getImage(icon)
      ..position = position.toLatLng();

    if (info != null || onTap != null) {
      _subscriptions.add(marker.onClick.listen((_) async {
        final key = position.toString();

        if (onTap != null) {
          onTap(key);
          return;
        }

        int doubleToInt(double value) => (value * 100000).truncate();
        final id = 'position${doubleToInt(position.latitude)}${doubleToInt(position.longitude)}';

        if (_infos[key] == null) {
          print(id);
          final _info = onInfoWindowTap == null
              ? '$info${infoSnippet.isNotEmpty == true ? '\n$infoSnippet' : ''}'
              : '<p id="$id">$info${infoSnippet.isNotEmpty == true ? '<p>$infoSnippet</p>' : ''}</p>';

          _infos[key] = InfoWindow(InfoWindowOptions()..content = _info);
          _subscriptions.add(_infos[key].onCloseclick.listen((_) => _infoState[key] = false));
        }

        if (!(_infoState[key] ?? false)) {
          _infos[key].open(_map, marker);
          if (_infoState[key] == null) {
            await Future.delayed(const Duration(milliseconds: 100));

            final infoElem =
                querySelector('flt-platform-view').shadowRoot.getElementById('$htmlId').querySelector('#$id');

            infoElem.addEventListener('click', (event) => onInfoWindowTap());
          }
          _infoState[key] = true;
        } else {
          _infos[key].close();

          _infoState[key] = false;
        }
      }));
    }

    _markers[key] = marker;
  }

  @override
  void addMarker(items.Marker marker) => addMarkerRaw(
        marker.position,
        label: marker.label,
        icon: marker.icon,
        info: marker.info,
        infoSnippet: marker.infoSnippet,
        onTap: marker.onTap,
        onInfoWindowTap: marker.onInfoWindowTap,
      );

  @override
  void removeMarker(GeoCoord position) {
    assert(() {
      if (position == null) {
        throw ArgumentError.notNull('position');
      }

      if (position.latitude == null || position.longitude == null) {
        throw ArgumentError.notNull('position.latitude && position.longitude');
      }

      return true;
    }());

    final key = position.toString();

    var marker = _markers.remove(key);
    marker?.map = null;
    marker = null;

    var info = _infos.remove(key);
    info?.close();
    info = null;

    _infoState.remove(key);
  }

  @override
  void clearMarkers() {
    for (var marker in _markers.values) {
      marker?.map = null;
      marker = null;
    }
    _markers.clear();

    for (var info in _infos.values) {
      info?.close();
      info = null;
    }
    _infos.clear();

    _infoState.clear();
  }

  @override
  void addDirection(
    dynamic origin,
    dynamic destination, {
    String startLabel,
    String startIcon,
    String startInfo,
    String endLabel,
    String endIcon,
    String endInfo,
  }) {
    assert(() {
      if (origin == null) {
        throw ArgumentError.notNull('origin');
      }

      if (destination == null) {
        throw ArgumentError.notNull('destination');
      }

      return true;
    }());

    _directions.putIfAbsent(
      '${origin}_$destination',
      () {
        DirectionsRenderer direction = DirectionsRenderer(DirectionsRendererOptions()..suppressMarkers = true);
        direction.map = _map;

        final request = DirectionsRequest()
          ..origin = origin is GeoCoord ? LatLng(origin.latitude, origin.longitude) : origin
          ..destination = destination is GeoCoord ? destination.toLatLng() : destination
          ..travelMode = TravelMode.DRIVING;
        directionsService.route(
          request,
          (response, status) {
            if (status == DirectionsStatus.OK) {
              direction.directions = response;

              final leg = response?.routes?.firstOrNull?.legs?.firstOrNull;

              final startLatLng = leg?.startLocation;
              if (startLatLng != null) {
                if (startIcon != null || startInfo != null || startLabel != null) {
                  addMarkerRaw(
                    startLatLng.toGeoCoord(),
                    icon: startIcon,
                    info: startInfo ?? leg.startAddress,
                    label: startLabel,
                  );
                } else {
                  addMarkerRaw(
                    startLatLng.toGeoCoord(),
                    icon: 'assets/images/marker_a.png',
                    info: leg.startAddress,
                  );
                }
              }

              final endLatLng = leg?.endLocation;
              if (endLatLng != null) {
                if (endIcon != null || endInfo != null || endLabel != null) {
                  addMarkerRaw(
                    endLatLng.toGeoCoord(),
                    icon: endIcon,
                    info: endInfo ?? leg.endAddress,
                    label: endLabel,
                  );
                } else {
                  addMarkerRaw(
                    endLatLng.toGeoCoord(),
                    icon: 'assets/images/marker_b.png',
                    info: leg.endAddress,
                  );
                }
              }
            }
          },
        );

        return direction;
      },
    );
  }

  @override
  void removeDirection(dynamic origin, dynamic destination) {
    assert(() {
      if (origin == null) {
        throw ArgumentError.notNull('origin');
      }

      if (destination == null) {
        throw ArgumentError.notNull('destination');
      }

      return true;
    }());

    var value = _directions.remove('${origin}_$destination');
    value?.map = null;
    final start = value?.directions?.routes?.firstOrNull?.legs?.firstOrNull?.startLocation?.toGeoCoord();
    if (start != null) {
      removeMarker(start);
    }
    final end = value?.directions?.routes?.firstOrNull?.legs?.lastOrNull?.endLocation?.toGeoCoord();
    if (end != null) {
      removeMarker(end);
    }
    value = null;
  }

  @override
  void clearDirections() {
    for (var direction in _directions.values) {
      direction?.map = null;
      final start = direction?.directions?.routes?.firstOrNull?.legs?.firstOrNull?.startLocation?.toGeoCoord();
      if (start != null) {
        removeMarker(start);
      }
      final end = direction?.directions?.routes?.firstOrNull?.legs?.lastOrNull?.endLocation?.toGeoCoord();
      if (end != null) {
        removeMarker(end);
      }
      direction = null;
    }
    _directions.clear();
  }

  @override
  void addPolygon(
    String id,
    Iterable<GeoCoord> points, {
    ValueChanged<String> onTap,
    Color strokeColor = const Color(0x000000),
    double strokeOpacity = 0.8,
    double strokeWidth = 1,
    Color fillColor = const Color(0x000000),
    double fillOpacity = 0.35,
  }) {
    assert(() {
      if (id == null) {
        throw ArgumentError.notNull('id');
      }

      if (points == null) {
        throw ArgumentError.notNull('position');
      }

      if (points.isEmpty) {
        throw ArgumentError.value(<GeoCoord>[], 'points');
      }

      if (points.length < 3) {
        throw ArgumentError('Polygon must have at least 3 coordinates');
      }

      return true;
    }());

    _polygons.putIfAbsent(
      id,
      () {
        final options = PolygonOptions()
          ..clickable = onTap != null
          ..paths = points.mapList((_) => _.toLatLng())
          ..strokeColor = strokeColor?.toHashString() ?? '#000000'
          ..strokeOpacity = strokeOpacity ?? 0.8
          ..strokeWeight = strokeWidth ?? 1
          ..fillColor = strokeColor?.toHashString() ?? '#000000'
          ..fillOpacity = fillOpacity ?? 0.35;

        final polygon = Polygon(options)..map = _map;

        if (onTap != null) {
          _subscriptions.add(polygon.onClick.listen((_) => onTap(id)));
        }

        return polygon;
      },
    );
  }

  @override
  void editPolygon(
    String id,
    Iterable<GeoCoord> points, {
    ValueChanged<String> onTap,
    Color strokeColor = const Color(0x000000),
    double strokeOpacity = 0.8,
    double strokeWeight = 1,
    Color fillColor = const Color(0x000000),
    double fillOpacity = 0.35,
  }) {
    removePolygon(id);
    addPolygon(
      id,
      points,
      onTap: onTap,
      strokeColor: strokeColor,
      strokeOpacity: strokeOpacity,
      strokeWidth: strokeWeight,
      fillColor: fillColor,
      fillOpacity: fillOpacity,
    );
  }

  @override
  void removePolygon(String id) {
    assert(() {
      if (id == null) {
        throw ArgumentError.notNull('id');
      }

      return true;
    }());

    var value = _polygons.remove(id);
    value?.map = null;
    value = null;
  }

  @override
  void clearPolygons() {
    for (var polygon in _polygons.values) {
      polygon?.map = null;
      polygon = null;
    }
    _polygons.clear();
  }

  void _createMapOptions() {
    _mapOptions = MapOptions()
      ..zoom = widget.initialZoom
      ..center = widget.initialPosition.toLatLng()
      ..streetViewControl = widget.webPreferences.streetViewControl
      ..fullscreenControl = widget.webPreferences.fullscreenControl
      ..mapTypeControl = widget.webPreferences.mapTypeControl
      ..scrollwheel = widget.webPreferences.scrollwheel
      ..panControl = widget.webPreferences.panControl
      ..overviewMapControl = widget.webPreferences.overviewMapControl
      ..rotateControl = widget.webPreferences.rotateControl
      ..scaleControl = widget.webPreferences.scaleControl
      ..zoomControl = widget.webPreferences.zoomControl
      ..minZoom = widget.minZoom
      ..maxZoom = widget.maxZoom
      ..styles = widget.mapStyle?.parseMapStyle()
      ..mapTypeId = widget.mapType.toString().split('.')[1]
      ..gestureHandling = widget.interactive ? 'auto' : 'none';
  }

  @override
  void addCircle(
    String id,
    GeoCoord center,
    double radius, {
    ValueChanged<String> onTap,
    ui.Color strokeColor = const Color(0x000000),
    double strokeOpacity = 0.8,
    double strokeWidth = 1,
    ui.Color fillColor = const Color(0x000000),
    double fillOpacity = 0.35,
  }) {
    assert(() {
      if (id == null) {
        throw ArgumentError.notNull('id');
      }

      if (center == null) {
        throw ArgumentError.notNull('center');
      }

      if (radius == null) {
        throw ArgumentError.notNull('radius');
      }

      return true;
    }());

    _circles.putIfAbsent(
      id,
      () {
        final options = CircleOptions()
          ..center = center.toLatLng()
          ..radius = radius
          ..clickable = onTap != null
          ..strokeColor = strokeColor?.toHashString() ?? '#000000'
          ..strokeOpacity = strokeOpacity ?? 0.8
          ..strokeWeight = strokeWidth ?? 1
          ..fillColor = strokeColor?.toHashString() ?? '#000000'
          ..fillOpacity = fillOpacity ?? 0.35;

        final circle = Circle(options)..map = _map;

        if (onTap != null) {
          _subscriptions.add(circle.onClick.listen((_) => onTap(id)));
        }

        return circle;
      },
    );
  }

  @override
  void clearCircles() {
    for (var circle in _circles.values) {
      circle?.map = null;
      circle = null;
    }
    _circles.clear();
  }

  @override
  void editCircle(
    String id,
    GeoCoord center,
    double radius, {
    ValueChanged<String> onTap,
    ui.Color strokeColor = const Color(0x000000),
    double strokeOpacity = 0.8,
    double strokeWidth = 1,
    ui.Color fillColor = const Color(0x000000),
    double fillOpacity = 0.35,
  }) {
    removeCircle(id);
    addCircle(
      id,
      center,
      radius,
      onTap: onTap,
      strokeColor: strokeColor,
      strokeOpacity: strokeOpacity,
      strokeWidth: strokeWidth,
      fillColor: fillColor,
      fillOpacity: fillOpacity,
    );
  }

  @override
  void removeCircle(String id) {
    assert(() {
      if (id == null) {
        throw ArgumentError.notNull('id');
      }

      return true;
    }());

    var value = _circles.remove(id);
    value?.map = null;
    value = null;
  }

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (var marker in widget.markers) {
        addMarker(marker);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _createMapOptions();

    if (_map == null) {
      ui.platformViewRegistry.registerViewFactory(htmlId, (int viewId) {
        final elem = DivElement()
          ..id = htmlId
          ..style.width = '100%'
          ..style.zIndex = '10'
          ..style.height = '100%'
          ..style.border = 'none'
          ..style.zIndex = '999';

        _map = GMap(elem, _mapOptions);

        _subscriptions.add(_map.onClick.listen((event) => widget.onTap?.call(event?.latLng?.toGeoCoord())));
        _subscriptions.add(_map.onRightclick.listen((event) => widget.onLongPress?.call(event?.latLng?.toGeoCoord())));

        return elem;
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onVerticalDragUpdate: widget.webPreferences.dragGestures ? null : (_) {},
        onHorizontalDragUpdate: widget.webPreferences.dragGestures ? null : (_) {},
        child: Container(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight),
          child: HtmlElementView(viewType: htmlId),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    _subscriptions.forEach((_) => _.cancel());

    _infos.clear();
    _markers.clear();
    _polygons.clear();
    _circles.clear();
    _infoState.clear();
    _directions.clear();
    _subscriptions.clear();

    _map = null;
    _mapOptions = null;
  }
}
