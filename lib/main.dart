// ══════════════════════════════════════════════════════════════════════════════
// ARCHITECTURE — IMPORTANT
// ══════════════════════════════════════════════════════════════════════════════
// Flutter MethodChannel allows only ONE active handler per channel name.
// The LAST widget to call setMethodCallHandler wins — all previous handlers
// stop receiving events silently, with no error.
//
// Fix applied here:
//  • HomeScreen owns the SINGLE handler for both nav and ble channels.
//  • Events are distributed downward via ValueNotifier<T>.
//  • NO child widget ever calls setMethodCallHandler itself.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';

void main() => runApp(const WayFindApp());

// ══════════════════════════════════════════════════════════════════════════════
// SHARED BLE EVENT MODEL
// ══════════════════════════════════════════════════════════════════════════════

class BleZoneEvent {
  final String zone;
  final int beaconCount;
  final Map<String, int> scanVector;
  final Map<String, String> beaconNames;

  const BleZoneEvent({
    required this.zone,
    required this.beaconCount,
    required this.scanVector,
    required this.beaconNames,
  });

  factory BleZoneEvent.empty() => const BleZoneEvent(
        zone: '—', beaconCount: 0, scanVector: {}, beaconNames: {});

  factory BleZoneEvent.fromJson(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final rv = data['scan_vector'] as Map<String, dynamic>? ?? {};
    final rn = data['beacon_names'] as Map<String, dynamic>? ?? {};
    return BleZoneEvent(
      zone: data['zone'] as String? ?? '—',
      beaconCount: data['beacon_count'] as int? ?? 0,
      scanVector: rv.map((k, v) => MapEntry(k, (v as num).toInt())),
      beaconNames: rn.map((k, v) => MapEntry(k, v as String)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MODELS
// ══════════════════════════════════════════════════════════════════════════════

class MapNode {
  final String name;
  final int x, y;
  final bool surveyed;

  const MapNode(
      {required this.name,
      required this.x,
      required this.y,
      this.surveyed = false});

  MapNode copyWith({bool? surveyed}) =>
      MapNode(name: name, x: x, y: y, surveyed: surveyed ?? this.surveyed);

  Map<String, dynamic> toJson() =>
      {'name': name, 'x': x, 'y': y, 'surveyed': surveyed};

  factory MapNode.fromJson(Map<String, dynamic> j) => MapNode(
      name: j['name'] as String,
      x: j['x'] as int,
      y: j['y'] as int,
      surveyed: j['surveyed'] as bool? ?? false);

  @override
  bool operator ==(Object other) => other is MapNode && other.name == name;
  @override
  int get hashCode => name.hashCode;
  @override
  String toString() => name;
}

class MapEdge {
  final String from, to;
  const MapEdge({required this.from, required this.to});
  Map<String, dynamic> toJson() => {'from': from, 'to': to};
  factory MapEdge.fromJson(Map<String, dynamic> j) =>
      MapEdge(from: j['from'] as String, to: j['to'] as String);
}

class FloorMap {
  final List<MapNode> nodes;
  final List<MapEdge> edges;
  const FloorMap({required this.nodes, required this.edges});

  Map<String, dynamic> toJson() => {
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
      };

  factory FloorMap.fromJson(Map<String, dynamic> j) => FloorMap(
      nodes: (j['nodes'] as List).map((n) => MapNode.fromJson(n)).toList(),
      edges: (j['edges'] as List).map((e) => MapEdge.fromJson(e)).toList());

  factory FloorMap.empty() => const FloorMap(nodes: [], edges: []);

  MapNode? nodeByName(String name) {
    try { return nodes.firstWhere((n) => n.name == name); } catch (_) { return null; }
  }

  List<String> neighborsOf(String name) {
    final r = <String>[];
    for (final e in edges) {
      if (e.from == name) r.add(e.to);
      if (e.to == name) r.add(e.from);
    }
    return r;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PATHFINDING
// ══════════════════════════════════════════════════════════════════════════════

class Pathfinder {
  static List<String>? findPath(FloorMap map, String start, String end) {
    if (start == end) return [start];
    final visited = <String>{start};
    final queue = <List<String>>[[start]];
    while (queue.isNotEmpty) {
      final path = queue.removeAt(0);
      final current = path.last;
      for (final nb in map.neighborsOf(current)) {
        if (nb == end) return [...path, nb];
        if (!visited.contains(nb)) {
          visited.add(nb);
          queue.add([...path, nb]);
        }
      }
    }
    return null;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DIRECTION HELPERS
// ══════════════════════════════════════════════════════════════════════════════

double vectorToCompassDegrees(int dx, int dy) =>
    (atan2(dx.toDouble(), dy.toDouble()) * 180 / pi + 360) % 360;

double angleDiff(double target, double current) {
  double d = (target - current + 360) % 360;
  if (d > 180) d -= 360;
  return d;
}

String turnInstruction(double diff) {
  final abs = diff.abs();
  final side = diff > 0 ? 'right' : 'left';
  if (abs < 15) return 'You are facing the right direction';
  if (abs < 45) return 'Turn slightly $side';
  if (abs < 90) return 'Turn $side';
  return 'Turn sharply $side';
}

String directionLabel(int dx, int dy) {
  if (dx == 0 && dy > 0) return 'North';
  if (dx == 0 && dy < 0) return 'South';
  if (dx > 0 && dy == 0) return 'East';
  if (dx < 0 && dy == 0) return 'West';
  return 'Unknown';
}

// ══════════════════════════════════════════════════════════════════════════════
// MAP STORAGE
// ══════════════════════════════════════════════════════════════════════════════

class MapStorage {
  static const _nav = MethodChannel('com.example.wayfind/nav');
  static Future<void> saveMap(FloorMap m) =>
      _nav.invokeMethod('saveMap', jsonEncode(m.toJson()));
  static Future<FloorMap> loadMap() async {
    try {
      final String? d = await _nav.invokeMethod<String>('loadMap');
      if (d == null || d.isEmpty) return FloorMap.empty();
      return FloorMap.fromJson(jsonDecode(d));
    } catch (_) { return FloorMap.empty(); }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// APP ROOT
// ══════════════════════════════════════════════════════════════════════════════

class WayFindApp extends StatelessWidget {
  const WayFindApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'WayFind',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true),
        home: const HomeScreen(),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// HOME SCREEN  ← OWNS ALL CHANNEL HANDLERS
// ══════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _navCh = MethodChannel('com.example.wayfind/nav');
  static const _bleCh = MethodChannel('com.example.wayfind/ble');

  // Shared notifiers — distributed to children
  final _bleZone    = ValueNotifier<BleZoneEvent>(BleZoneEvent.empty());
  final _surveyTick = ValueNotifier<int>(0);
  final _permission = ValueNotifier<bool>(false);
  final _compass    = ValueNotifier<double>(0.0);
  final _speech     = ValueNotifier<String>('');

  int _tab = 0;
  FloorMap _map = FloorMap.empty();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _registerHandlers();
    _loadMap();
    _checkPerms();
  }

  @override
  void dispose() {
    _bleZone.dispose(); _surveyTick.dispose();
    _permission.dispose(); _compass.dispose(); _speech.dispose();
    super.dispose();
  }

  // THE SINGLE handler registrations — never call setMethodCallHandler anywhere else
  void _registerHandlers() {
    _navCh.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onCompassUpdate':
          _compass.value = (call.arguments as num).toDouble();
          break;
        case 'onSpeechResult':
          _speech.value = ((call.arguments as String?) ?? '').toLowerCase().trim();
          break;
      }
    });

    _bleCh.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onZoneData':
          _bleZone.value = BleZoneEvent.fromJson(call.arguments as String);
          break;
        case 'onSurveyTick':
          _surveyTick.value = call.arguments as int;
          break;
        case 'onPermissionResult':
          _permission.value = call.arguments as bool;
          break;
      }
    });
  }

  Future<void> _checkPerms() async {
    try {
      _permission.value = await _bleCh.invokeMethod('checkPermissions');
    } catch (_) {}
  }

  Future<void> _loadMap() async {
    final m = await MapStorage.loadMap();
    setState(() { _map = m; _loading = false; });
  }

  Future<void> _updateMap(FloorMap m) async {
    await MapStorage.saveMap(m);
    setState(() => _map = m);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          MapEditorScreen(
              map: _map, onMapChanged: _updateMap,
              bleChannel: _bleCh,
              surveyTickNotifier: _surveyTick,
              permissionNotifier: _permission),
          NavigationScreen(
              map: _map,
              navChannel: _navCh, bleChannel: _bleCh,
              bleZoneNotifier: _bleZone,
              compassNotifier: _compass,
              speechNotifier: _speech),
          BleDebugScreen(
              bleChannel: _bleCh,
              bleZoneNotifier: _bleZone,
              surveyTickNotifier: _surveyTick,
              permissionNotifier: _permission),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map Editor'),
          NavigationDestination(icon: Icon(Icons.navigation_outlined), selectedIcon: Icon(Icons.navigation), label: 'Navigate'),
          NavigationDestination(icon: Icon(Icons.bluetooth_outlined), selectedIcon: Icon(Icons.bluetooth), label: 'BLE Debug'),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MAP EDITOR SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class MapEditorScreen extends StatefulWidget {
  final FloorMap map;
  final Future<void> Function(FloorMap) onMapChanged;
  final MethodChannel bleChannel;
  final ValueNotifier<int> surveyTickNotifier;
  final ValueNotifier<bool> permissionNotifier;

  const MapEditorScreen({
    super.key, required this.map, required this.onMapChanged,
    required this.bleChannel, required this.surveyTickNotifier,
    required this.permissionNotifier,
  });

  @override
  State<MapEditorScreen> createState() => _MapEditorScreenState();
}

class _MapEditorScreenState extends State<MapEditorScreen> {
  static const _dirs = {'North': (0, 1), 'South': (0, -1), 'East': (1, 0), 'West': (-1, 0)};

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _openWizard() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddLocationWizard(
        existingMap: widget.map,
        bleChannel: widget.bleChannel,
        surveyTickNotifier: widget.surveyTickNotifier,
        directionOffsets: _dirs,
        onFinished: widget.onMapChanged,
      ),
    );
  }

  Future<void> _deleteNode(String name) async {
    await widget.onMapChanged(FloorMap(
      nodes: widget.map.nodes.where((n) => n.name != name).toList(),
      edges: widget.map.edges.where((e) => e.from != name && e.to != name).toList(),
    ));
    widget.bleChannel.invokeMethod('deleteZone', {'zoneName': name}).catchError((_) {});
    _snack('Deleted "$name"');
  }

  Future<void> _clearMap() async {
    await widget.onMapChanged(FloorMap.empty());
    widget.bleChannel.invokeMethod('clearSurveys').catchError((_) {});
    _snack('Map cleared');
  }

  @override
  Widget build(BuildContext context) {
    final nodes = widget.map.nodes;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.inversePrimary,
        title: const Text('WayFind — Map Editor'),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: _showInfo),
          if (nodes.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () => _confirmClear(context)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (nodes.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(bottom: 6),
                      child: Text('Floor Map', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54))),
                  SizedBox(height: 160,
                      child: ClipRRect(borderRadius: BorderRadius.circular(8),
                          child: _MapVisualizer(map: widget.map))),
                ]),
              ),
            ),
            const SizedBox(height: 12),
          ],
          ElevatedButton.icon(
            onPressed: _openWizard,
            icon: const Icon(Icons.add_location_alt),
            label: Text(nodes.isEmpty ? 'Add First Location' : 'Add New Location'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          if (nodes.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 8),
                child: Text('⚠ First location becomes the map origin (0, 0).',
                    style: TextStyle(fontSize: 12, color: Colors.deepOrange))),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Saved Locations', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text('${nodes.length} location${nodes.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 13, color: Colors.black45)),
          ]),
          const SizedBox(height: 6),
          Expanded(
            child: nodes.isEmpty
                ? const Center(child: Text('No locations yet.\nTap "Add First Location" above.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black38)))
                : ListView.builder(
                    itemCount: nodes.length,
                    itemBuilder: (_, i) {
                      final n = nodes[i];
                      final nb = widget.map.neighborsOf(n.name);
                      return Card(child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: n.surveyed ? Colors.green : cs.primary,
                          child: Icon(n.surveyed ? Icons.wifi_tethering : Icons.location_on,
                              color: Colors.white, size: 18),
                        ),
                        title: Text(n.name),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(nb.isEmpty ? 'No connections' : 'Connected: ${nb.join(", ")}',
                              style: const TextStyle(fontSize: 12, color: Colors.black45)),
                          Text(n.surveyed ? '✓ BLE fingerprint recorded' : '⚠ No BLE fingerprint',
                              style: TextStyle(fontSize: 11,
                                  color: n.surveyed ? Colors.green[700] : Colors.orange[800],
                                  fontWeight: FontWeight.w500)),
                        ]),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _confirmDelete(context, n.name),
                        ),
                      ));
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, String name) => showDialog(
    context: ctx,
    builder: (_) => AlertDialog(
      title: const Text('Delete Location'),
      content: Text('Delete "$name" and all its connections?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () { Navigator.pop(ctx); _deleteNode(name); },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete')),
      ],
    ),
  );

  void _confirmClear(BuildContext ctx) => showDialog(
    context: ctx,
    builder: (_) => AlertDialog(
      title: const Text('Clear Map'),
      content: const Text('Delete all locations, connections and BLE fingerprints?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () { Navigator.pop(ctx); _clearMap(); },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All')),
      ],
    ),
  );

  void _showInfo() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('About WayFind'),
      content: const SingleChildScrollView(
        child: Text(
          'WayFind — Indoor Navigation + BLE Fingerprinting\n\n'
          'Adding a Location:\n'
          '1. Enter a name\n2. Select adjacent location and direction\n'
          '3. Record BLE fingerprint (~30 s)\n\n'
          'Navigation:\n'
          '• Pick source and destination\n'
          '• BLE scanning starts automatically\n'
          '• App auto-advances when zone confirmed twice in a row\n'
          '• Manual "I\'ve Arrived" always available',
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// ADD LOCATION WIZARD
// ══════════════════════════════════════════════════════════════════════════════

class AddLocationWizard extends StatefulWidget {
  final FloorMap existingMap;
  final MethodChannel bleChannel;
  final ValueNotifier<int> surveyTickNotifier;
  final Map<String, (int, int)> directionOffsets;
  final Future<void> Function(FloorMap) onFinished;

  const AddLocationWizard({
    super.key, required this.existingMap, required this.bleChannel,
    required this.surveyTickNotifier, required this.directionOffsets,
    required this.onFinished,
  });

  @override
  State<AddLocationWizard> createState() => _AddLocationWizardState();
}

class _AddLocationWizardState extends State<AddLocationWizard> {
  int _step = 0;
  final _nameCtrl = TextEditingController();
  String? _nameError, _selAdj, _selDir;
  bool _isScanning = false, _isSurveying = false, _surveyDone = false;
  int _sampleCount = 0;
  String _status = 'Start scanning, then begin recording.';
  MapNode? _pendingNode;
  MapEdge? _pendingEdge;

  @override
  void initState() {
    super.initState();
    widget.surveyTickNotifier.addListener(_onTick);
  }

  void _onTick() {
    if (!mounted) return;
    setState(() { _sampleCount = widget.surveyTickNotifier.value; _status = 'Recording… $_sampleCount samples collected'; });
  }

  @override
  void dispose() {
    widget.surveyTickNotifier.removeListener(_onTick);
    _nameCtrl.dispose();
    if (_isSurveying) widget.bleChannel.invokeMethod('cancelSurvey').catchError((_) {});
    if (_isScanning) widget.bleChannel.invokeMethod('stopScanning').catchError((_) {});
    super.dispose();
  }

  bool get _isFirst => widget.existingMap.nodes.isEmpty;

  bool _v1() {
    final n = _nameCtrl.text.trim();
    if (n.isEmpty) { setState(() => _nameError = 'Enter a name'); return false; }
    if (widget.existingMap.nodeByName(n) != null) { setState(() => _nameError = '"$n" already exists'); return false; }
    setState(() => _nameError = null); return true;
  }

  bool _v2() {
    if (_isFirst) return true;
    if (_selAdj == null) { _snack('Select an adjacent location'); return false; }
    if (_selDir == null) { _snack('Select a direction'); return false; }
    final a = widget.existingMap.nodeByName(_selAdj!)!;
    final o = widget.directionOffsets[_selDir!]!;
    if (widget.existingMap.nodes.any((n) => n.x == a.x + o.$1 && n.y == a.y + o.$2)) {
      _snack('A location already exists at that position'); return false;
    }
    return true;
  }

  void _buildNode() {
    final name = _nameCtrl.text.trim();
    if (_isFirst) {
      _pendingNode = MapNode(name: name, x: 0, y: 0); _pendingEdge = null;
    } else {
      final a = widget.existingMap.nodeByName(_selAdj!)!;
      final o = widget.directionOffsets[_selDir!]!;
      _pendingNode = MapNode(name: name, x: a.x + o.$1, y: a.y + o.$2);
      _pendingEdge = MapEdge(from: _selAdj!, to: name);
    }
  }

  Future<void> _startScan() async {
    try {
      await widget.bleChannel.invokeMethod('startScanning');
      setState(() { _isScanning = true; _status = 'Scanning active. Tap "Start Recording" when ready.'; });
    } catch (e) { setState(() => _status = 'Error: $e'); }
  }

  Future<void> _startSurvey() async {
    try {
      await widget.bleChannel.invokeMethod('startSurvey', {'zoneName': _pendingNode!.name});
      setState(() { _isSurveying = true; _sampleCount = 0; _status = 'Recording… 0 samples collected'; });
    } catch (e) { setState(() => _status = 'Error: $e'); }
  }

  Future<void> _stopSurvey() async {
    try {
      final String? saved = await widget.bleChannel.invokeMethod<String>('stopSurvey');
      setState(() {
        _isSurveying = false; _surveyDone = saved != null;
        _status = saved != null ? '✓ Fingerprint saved for "$saved" ($_sampleCount samples)' : '⚠ No data — try again';
      });
    } catch (e) { setState(() => _status = 'Error: $e'); }
  }

  Future<void> _finish() async {
    final fn = _pendingNode!.copyWith(surveyed: _surveyDone);
    final nn = [...widget.existingMap.nodes, fn];
    final ne = _pendingEdge != null ? [...widget.existingMap.edges, _pendingEdge!] : widget.existingMap.edges.toList();
    await widget.onFinished(FloorMap(nodes: nn, edges: ne));
    if (_isScanning) widget.bleChannel.invokeMethod('stopScanning').catchError((_) {});
    if (mounted) Navigator.pop(context);
  }

  Future<void> _cancel() async {
    if (_isSurveying) widget.bleChannel.invokeMethod('cancelSurvey').catchError((_) {});
    if (_isScanning) widget.bleChannel.invokeMethod('stopScanning').catchError((_) {});
    if (mounted) Navigator.pop(context);
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  bool _isLast() => _isFirst ? _step == 1 : _step == 2;

  VoidCallback? _nextOrFinish() {
    if (_isLast()) return _finish;
    return () {
      if (_step == 0) {
        if (!_v1()) return;
        if (_isFirst) _buildNode();
        setState(() => _step = 1);
      } else if (_step == 1 && !_isFirst) {
        if (!_v2()) return;
        _buildNode();
        setState(() => _step = 2);
      }
    };
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.add_location_alt, color: Colors.blue), const SizedBox(width: 8),
          Expanded(child: Text('Add Location — Step ${_step + 1} of ${_isFirst ? 2 : 3}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: (_step + 1) / (_isFirst ? 2 : 3), borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 20),
        if (_step == 0) _s1(),
        if (_step == 1 && !_isFirst) _s2(),
        if ((_step == 1 && _isFirst) || (_step == 2 && !_isFirst)) _sSurvey(),
        const SizedBox(height: 20),
        Row(children: [
          TextButton(onPressed: _cancel, child: const Text('Cancel')),
          const Spacer(),
          if (_step > 0) ...[
            OutlinedButton(onPressed: () => setState(() => _step--), child: const Text('Back')),
            const SizedBox(width: 8),
          ],
          ElevatedButton(onPressed: _nextOrFinish(), child: Text(_isLast() ? 'Add Location' : 'Next')),
        ]),
      ]),
    ),
  );

  Widget _s1() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Enter a name for this location:', style: TextStyle(fontSize: 14, color: Colors.black54)),
    const SizedBox(height: 10),
    TextField(
      controller: _nameCtrl, autofocus: true,
      decoration: InputDecoration(labelText: 'Location name', hintText: 'e.g. Corridor North, Room A…',
          border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.location_on_outlined), errorText: _nameError),
      textCapitalization: TextCapitalization.words,
      onChanged: (_) => setState(() => _nameError = null),
    ),
  ]);

  Widget _s2() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Where is "${_nameCtrl.text.trim()}" relative to an existing location?',
        style: const TextStyle(fontSize: 14, color: Colors.black54)),
    const SizedBox(height: 12),
    DropdownButtonFormField<String>(
      value: _selAdj,
      decoration: const InputDecoration(labelText: 'Adjacent to', border: OutlineInputBorder(), prefixIcon: Icon(Icons.link)),
      items: widget.existingMap.nodes.map((n) => DropdownMenuItem(value: n.name, child: Text(n.name, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) => setState(() => _selAdj = v),
    ),
    const SizedBox(height: 12),
    DropdownButtonFormField<String>(
      value: _selDir,
      decoration: const InputDecoration(labelText: 'Direction', border: OutlineInputBorder(), prefixIcon: Icon(Icons.explore_outlined)),
      items: ['North', 'South', 'East', 'West'].map((d) => DropdownMenuItem(value: d,
          child: Row(children: [Text(_dIcon(d)), const SizedBox(width: 8), Text(d)]))).toList(),
      onChanged: (v) => setState(() => _selDir = v),
    ),
  ]);

  Widget _sSurvey() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Record BLE Fingerprint', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Stand in "${_pendingNode?.name ?? ""}" and record BLE signals for ~30 seconds.',
            style: const TextStyle(fontSize: 13, color: Colors.black54)),
      ]),
    ),
    const SizedBox(height: 14),
    Card(
      color: _surveyDone ? Colors.green[50] : _isSurveying ? Colors.orange[50] : Colors.grey[50],
      child: Padding(padding: const EdgeInsets.all(12),
        child: Row(children: [
          if (_isSurveying) const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14)
          else if (_surveyDone) const Icon(Icons.check_circle, color: Colors.green, size: 18)
          else const Icon(Icons.info_outline, color: Colors.grey, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_status, style: TextStyle(fontSize: 13,
              color: _isSurveying ? Colors.red[800] : Colors.black87,
              fontWeight: _isSurveying ? FontWeight.w500 : FontWeight.normal))),
        ]),
      ),
    ),
    const SizedBox(height: 12),
    if (!_isScanning) ElevatedButton.icon(onPressed: _startScan,
        icon: const Icon(Icons.bluetooth_searching), label: const Text('Start BLE Scanning'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white)),
    if (_isScanning && !_isSurveying && !_surveyDone) ElevatedButton.icon(onPressed: _startSurvey,
        icon: const Icon(Icons.fiber_manual_record), label: const Text('Start Recording'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white)),
    if (_isSurveying) ElevatedButton.icon(onPressed: _stopSurvey,
        icon: const Icon(Icons.save), label: Text('Stop & Save  ($_sampleCount samples)'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
    if (_surveyDone) ...[
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => setState(() { _surveyDone = false; _sampleCount = 0; _status = 'Tap "Start Recording" to redo.'; }),
        icon: const Icon(Icons.refresh), label: const Text('Re-record fingerprint'),
      ),
    ],
    if (!_surveyDone) Padding(padding: const EdgeInsets.only(top: 8),
        child: TextButton(onPressed: _finish,
            child: const Text('Skip survey (not recommended)', style: TextStyle(color: Colors.black45)))),
  ]);

  String _dIcon(String d) => const {'North': '↑', 'South': '↓', 'East': '→', 'West': '←'}[d] ?? '?';
}

// ══════════════════════════════════════════════════════════════════════════════
// MAP VISUALIZER
// ══════════════════════════════════════════════════════════════════════════════

class _MapVisualizer extends StatelessWidget {
  final FloorMap map;
  final String? highlightNode, nextNode;
  const _MapVisualizer({required this.map, this.highlightNode, this.nextNode});

  @override
  Widget build(BuildContext context) => CustomPaint(
      painter: _MapPainter(map, Theme.of(context).colorScheme.primary, highlightNode, nextNode),
      child: const SizedBox.expand());
}

class _MapPainter extends CustomPainter {
  final FloorMap map;
  final Color primary;
  final String? hl, nxt;
  _MapPainter(this.map, this.primary, this.hl, this.nxt);

  @override
  void paint(Canvas canvas, Size size) {
    if (map.nodes.isEmpty) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blue.shade50);
    final ep = Paint()..color = primary.withOpacity(0.4)..strokeWidth = 2;
    final xs = map.nodes.map((n) => n.x.toDouble()).toList();
    final ys = map.nodes.map((n) => n.y.toDouble()).toList();
    final minX = xs.reduce(min), maxX = xs.reduce(max);
    final minY = ys.reduce(min), maxY = ys.reduce(max);
    const pad = 28.0;
    final scale = min((size.width - pad * 2) / (maxX - minX).clamp(1, double.infinity),
        (size.height - pad * 2) / (maxY - minY).clamp(1, double.infinity));
    Offset ts(int x, int y) => Offset(
      pad + (x - minX) * scale + (size.width - pad * 2 - (maxX - minX).clamp(1, double.infinity) * scale) / 2,
      size.height - pad - (y - minY) * scale - (size.height - pad * 2 - (maxY - minY).clamp(1, double.infinity) * scale) / 2,
    );
    for (final e in map.edges) {
      final f = map.nodeByName(e.from), t = map.nodeByName(e.to);
      if (f != null && t != null) canvas.drawLine(ts(f.x, f.y), ts(t.x, t.y), ep);
    }
    for (final n in map.nodes) {
      final p = ts(n.x, n.y);
      final isHL = n.name == hl, isNxt = n.name == nxt;
      canvas.drawCircle(p, isHL ? 11 : isNxt ? 9 : 8,
          Paint()..color = isHL ? Colors.green : isNxt ? Colors.orange : primary);
      final tp = TextPainter(
        text: TextSpan(text: n.name, style: TextStyle(
            color: isHL ? Colors.green[900] : isNxt ? Colors.orange[900] : Colors.black87,
            fontSize: 9, fontWeight: (isHL || isNxt) ? FontWeight.bold : FontWeight.w500)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 80);
      tp.paint(canvas, p.translate(-tp.width / 2, 12));
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.hl != hl || old.nxt != nxt || old.map != map;
}

// ══════════════════════════════════════════════════════════════════════════════
// NAVIGATION SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class NavigationScreen extends StatefulWidget {
  final FloorMap map;
  final MethodChannel navChannel, bleChannel;
  final ValueNotifier<BleZoneEvent> bleZoneNotifier;
  final ValueNotifier<double> compassNotifier;
  final ValueNotifier<String> speechNotifier;

  const NavigationScreen({
    super.key, required this.map, required this.navChannel, required this.bleChannel,
    required this.bleZoneNotifier, required this.compassNotifier, required this.speechNotifier,
  });

  @override
  State<NavigationScreen> createState() => _NavState();
}

class _NavState extends State<NavigationScreen> {
  // Route
  String? _src, _dst;
  List<String>? _path;
  int _step = 0;

  // Compass
  double _heading = 0, _targetHeading = 0;
  String _turnInst = '';
  bool _compassActive = false;

  // TTS
  final FlutterTts _tts = FlutterTts();
  String _lastSpoken = '';

  // STT
  bool _listening = false, _listenForSrc = false;

  // BLE
  bool _bleScan = false;
  BleZoneEvent _ble = BleZoneEvent.empty();
  String? _lastZone;
  int _consec = 0;
  static const _thresh = 2;
  bool _srcConfirmed = false;
  String? _advanceMsg;

  @override
  void initState() {
    super.initState();
    _initTts();
    _startCompass();
    widget.bleZoneNotifier.addListener(_onBle);
    widget.compassNotifier.addListener(_onCompass);
    widget.speechNotifier.addListener(_onSpeech);
  }

  @override
  void dispose() {
    widget.bleZoneNotifier.removeListener(_onBle);
    widget.compassNotifier.removeListener(_onCompass);
    widget.speechNotifier.removeListener(_onSpeech);
    _stopBle();
    widget.navChannel.invokeMethod('stopCompass').catchError((_) {});
    _tts.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty || text == _lastSpoken) return;
    _lastSpoken = text;
    await _tts.stop();
    await _tts.speak(text);
  }

  void _onBle() {
    if (!mounted) return;
    final e = widget.bleZoneNotifier.value;
    setState(() => _ble = e);
    _handleZone(e.zone);
  }

  void _onCompass() {
    if (!mounted) return;
    setState(() {
      _heading = widget.compassNotifier.value;
      if (_compassActive) _updateTurn();
    });
  }

  void _onSpeech() {
    if (!mounted) return;
    final s = widget.speechNotifier.value;
    setState(() => _listening = false);
    if (s.isNotEmpty) _matchVoice(s, isSource: _listenForSrc);
  }

  void _handleZone(String zone) {
    if (_path == null) return;
    // Source confirmation
    if (!_srcConfirmed && zone == _path![0]) {
      setState(() => _srcConfirmed = true);
      _speak('Position confirmed. You are at ${_path![0]}.');
    }
    // Debounce
    if (zone == _lastZone) { _consec++; } else { _consec = 1; _lastZone = zone; }
    if (_consec < _thresh || _step >= _path!.length - 1) return;
    // Look-ahead
    for (int i = _step + 1; i < _path!.length; i++) {
      if (_path![i] == zone) { _goToStep(i, byBle: true); return; }
    }
  }

  Future<void> _startBle() async {
    if (_bleScan) return;
    try {
      final bool ok = await widget.bleChannel.invokeMethod('startScanning');
      if (ok && mounted) setState(() => _bleScan = true);
    } catch (_) {}
  }

  Future<void> _stopBle() async {
    if (!_bleScan) return;
    try { await widget.bleChannel.invokeMethod('stopScanning'); } catch (_) {}
    if (mounted) setState(() => _bleScan = false);
  }

  Future<void> _startCompass() async {
    try { await widget.navChannel.invokeMethod('startCompass'); } catch (_) {}
  }

  Future<void> _computeRoute() async {
    if (_src == null || _dst == null) return;
    if (_src == _dst) { _snack('Source and destination are the same'); return; }
    final path = Pathfinder.findPath(widget.map, _src!, _dst!);
    if (path == null) { _snack('No path found'); setState(() { _path = null; _step = 0; }); return; }
    setState(() {
      _path = path; _step = 0; _compassActive = true; _lastSpoken = '';
      _advanceMsg = null; _srcConfirmed = false; _lastZone = null; _consec = 0;
      _updateTurn();
    });
    await _startBle();
    _speak('Starting navigation. Head to ${path.length > 1 ? path[1] : path[0]}.');
  }

  void _updateTurn() {
    if (_path == null || _step >= _path!.length - 1) { setState(() => _turnInst = ''); return; }
    final cur = widget.map.nodeByName(_path![_step]);
    final nxt = widget.map.nodeByName(_path![_step + 1]);
    if (cur == null || nxt == null) return;
    _targetHeading = vectorToCompassDegrees(nxt.x - cur.x, nxt.y - cur.y);
    final inst = turnInstruction(angleDiff(_targetHeading, _heading));
    setState(() => _turnInst = inst);
    if (_compassActive) _speak(inst);
  }

  void _goToStep(int target, {bool byBle = false}) {
    if (_path == null || target >= _path!.length) return;
    final isLast = target == _path!.length - 1;
    setState(() {
      _step = target; _lastSpoken = ''; _consec = 0; _lastZone = null;
      _advanceMsg = byBle ? '📍 BLE confirmed: "${_path![target]}"' : null;
      _updateTurn();
    });
    if (byBle) Future.delayed(const Duration(seconds: 4), () { if (mounted) setState(() => _advanceMsg = null); });
    if (isLast) { _speak('You have arrived at ${_path!.last}. Navigation complete.'); _stopBle(); }
    else _speak('Arrived. Now head to ${_path![target + 1]}.');
  }

  void _manualAdvance() => _goToStep(_step + 1);

  Future<void> _endNav() async {
    await _stopBle();
    setState(() {
      _path = null; _step = 0; _compassActive = false; _turnInst = '';
      _src = null; _dst = null; _advanceMsg = null;
      _srcConfirmed = false; _lastZone = null; _consec = 0;
    });
  }

  Future<void> _listen({required bool isSource}) async {
    setState(() { _listening = true; _listenForSrc = isSource; });
    await _tts.stop();
    await _tts.speak(isSource ? 'Which location are you starting from?' : 'Which location do you want to go to?');
    await Future.delayed(const Duration(milliseconds: 2500));
    try { await widget.navChannel.invokeMethod('startSpeechInput', isSource ? 'Starting location?' : 'Destination?'); }
    catch (e) { setState(() => _listening = false); _snack('Speech not available'); }
  }

  void _matchVoice(String spoken, {required bool isSource}) {
    String? matched;
    for (final n in widget.map.nodes) { if (spoken.contains(n.name.toLowerCase())) { matched = n.name; break; } }
    if (matched != null) {
      setState(() { if (isSource) _src = matched; else _dst = matched; });
      _speak('${isSource ? 'Starting from' : 'Going to'} $matched.');
    } else {
      _speak('Sorry, I did not recognize that location. Please try again.');
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final nodes = widget.map.nodes;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('WayFind — Navigate'),
        actions: [
          if (_bleScan) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bluetooth_searching, color: Colors.blue[700], size: 18),
              const SizedBox(width: 4),
              Text('BLE', style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.w600)),
            ]),
          ),
          if (_path != null) IconButton(icon: const Icon(Icons.close), onPressed: _endNav),
        ],
      ),
      body: nodes.isEmpty ? _empty() : _path == null ? _picker(nodes) : _active(),
    );
  }

  Widget _empty() => const Center(
    child: Padding(padding: EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.map_outlined, size: 64, color: Colors.black26),
        SizedBox(height: 16),
        Text('No map loaded.', style: TextStyle(fontSize: 18, color: Colors.black54)),
        SizedBox(height: 6),
        Text('Go to Map Editor and add locations first.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.black38)),
      ]),
    ),
  );

  Widget _picker(List<MapNode> nodes) {
    final items = nodes.map((n) => DropdownMenuItem(value: n.name, child: Text(n.name))).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _bleCard(inNav: false),
        const SizedBox(height: 16),
        Card(
          color: Colors.blue[50],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Plan Your Route', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(
                  value: _src,
                  decoration: const InputDecoration(labelText: 'From', border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.trip_origin), filled: true, fillColor: Colors.white),
                  items: items, onChanged: (v) => setState(() => _src = v),
                )),
                const SizedBox(width: 8),
                _mic(isSource: true),
              ]),
              const SizedBox(height: 8),
              const Center(child: Icon(Icons.arrow_downward, color: Colors.blue, size: 28)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(
                  value: _dst,
                  decoration: const InputDecoration(labelText: 'To', border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on), filled: true, fillColor: Colors.white),
                  items: items, onChanged: (v) => setState(() => _dst = v),
                )),
                const SizedBox(width: 8),
                _mic(isSource: false),
              ]),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _src != null && _dst != null ? _computeRoute : null,
                  icon: const Icon(Icons.navigation),
                  label: const Text('Start Navigation', style: TextStyle(fontSize: 15)),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _mic({required bool isSource}) {
    final active = _listening && _listenForSrc == isSource;
    return Container(
      decoration: BoxDecoration(
          color: active ? Colors.red[50] : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: active ? Colors.red : Colors.blue)),
      child: IconButton(
        icon: Icon(active ? Icons.mic : Icons.mic_none, color: active ? Colors.red : Colors.blue),
        onPressed: () => _listen(isSource: isSource),
      ),
    );
  }

  Widget _active() {
    final path = _path!;
    final isLast = _step >= path.length - 1;
    final cur = path[_step];
    final nxt = isLast ? null : path[_step + 1];
    String dl = '';
    if (!isLast) {
      final cn = widget.map.nodeByName(cur), nn = widget.map.nodeByName(nxt!);
      if (cn != null && nn != null) dl = directionLabel(nn.x - cn.x, nn.y - cn.y);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _progressCard(path),
        const SizedBox(height: 10),
        SizedBox(height: 110, child: Card(
          child: Padding(padding: const EdgeInsets.all(6),
            child: ClipRRect(borderRadius: BorderRadius.circular(6),
                child: _MapVisualizer(map: widget.map, highlightNode: cur, nextNode: nxt))),
        )),
        const SizedBox(height: 10),
        _bleCard(inNav: true),
        const SizedBox(height: 8),
        // Current location
        Card(
          color: Colors.blue[50],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Column(children: [
              const Text('Current Location',
                  style: TextStyle(fontSize: 12, color: Colors.black54, letterSpacing: 1.1)),
              const SizedBox(height: 4),
              Text(cur, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary)),
              if (_step == 0) ...[
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(_srcConfirmed ? Icons.check_circle : Icons.sensors, size: 14,
                      color: _srcConfirmed ? Colors.green[700] : Colors.orange[700]),
                  const SizedBox(width: 4),
                  Text(_srcConfirmed ? 'Position confirmed' : 'Waiting for BLE position fix…',
                      style: TextStyle(fontSize: 11,
                          color: _srcConfirmed ? Colors.green[700] : Colors.orange[700])),
                ]),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 8),
        if (!isLast) ...[
          _dirCard(nxt!, dl),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _manualAdvance,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text("I've Arrived — Next Step", style: TextStyle(fontSize: 15)),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          const SizedBox(height: 10),
          _routeOverview(path),
        ] else ...[
          Card(
            color: Colors.green[50],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(children: [
                Icon(Icons.check_circle, color: Colors.green, size: 56),
                SizedBox(height: 10),
                Text('Destination Reached!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _endNav,
            icon: const Icon(Icons.replay),
            label: const Text('Plan New Route', style: TextStyle(fontSize: 15)),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ],
      ]),
    );
  }

  Widget _bleCard({required bool inNav}) {
    final isAdv = inNav && _advanceMsg != null;
    final isPend = inNav && !isAdv && _consec > 0 && _consec < _thresh && _ble.zone != '—';
    return Card(
      color: isAdv ? Colors.green.shade50 : isPend ? Colors.orange.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
              isAdv ? Icons.check_circle : _bleScan ? Icons.bluetooth_searching : Icons.bluetooth,
              color: isAdv ? Colors.green : _bleScan ? Colors.blue : Colors.grey, size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isAdv ? _advanceMsg! : 'BLE Zone: ${_ble.zone}',
                  style: TextStyle(fontSize: 13,
                      color: isAdv ? Colors.green[800] : Colors.black54,
                      fontWeight: isAdv ? FontWeight.w600 : FontWeight.normal)),
              if (isPend) Text('Confirming… ($_consec/$_thresh)',
                  style: TextStyle(fontSize: 11, color: Colors.orange[800])),
              if (!_bleScan && inNav)
                const Text('BLE not scanning', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ])),
            if (_ble.beaconCount > 0)
              Text('${_ble.beaconCount} beacon${_ble.beaconCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11, color: Colors.black38)),
          ]),
          if (_ble.scanVector.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 6),
            ..._ble.scanVector.entries.map((e) => _rssi(e.key, e.value)),
          ],
        ]),
      ),
    );
  }

  Widget _progressCard(List<String> path) {
    final progress = path.length <= 1 ? 1.0 : _step / (path.length - 1);
    return Card(
      child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Step ${_step + 1} of ${path.length}', style: const TextStyle(fontSize: 13, color: Colors.black54)),
          Text('${(progress * 100).toStringAsFixed(0)}% complete',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: Colors.grey[200])),
      ])),
    );
  }

  Widget _dirCard(String nextName, String dl) {
    final diff = angleDiff(_targetHeading, _heading);
    final aligned = diff.abs() < 15;
    return Card(
      color: aligned ? Colors.green[50] : Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.arrow_forward, color: aligned ? Colors.green : Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Head to', style: TextStyle(fontSize: 12, color: Colors.black54, letterSpacing: 1)),
              Text(nextName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ])),
            SizedBox(width: 52, height: 52,
                child: CustomPaint(painter: _ArrowPainter(
                    angle: ((_targetHeading - _heading) * pi / 180),
                    color: Theme.of(context).colorScheme.primary))),
          ]),
          const Divider(height: 16),
          Row(children: [
            const Icon(Icons.explore, color: Colors.black38, size: 16), const SizedBox(width: 6),
            Text('Face $dl  •  ${_targetHeading.toStringAsFixed(0)}°',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Icon(aligned ? Icons.check_circle : Icons.rotate_right,
                color: aligned ? Colors.green : Colors.orange, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(_turnInst.isEmpty ? 'Calculating…' : _turnInst,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: aligned ? Colors.green[700] : Colors.orange[800]))),
          ]),
          const SizedBox(height: 2),
          Text('Your heading: ${_heading.toStringAsFixed(0)}°',
              style: const TextStyle(fontSize: 11, color: Colors.black38)),
        ]),
      ),
    );
  }

  Widget _routeOverview(List<String> path) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Route Overview', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      ...List.generate(path.length, (i) {
        final past = i < _step, cur = i == _step, last = i == path.length - 1;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 28, child: Column(children: [
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  color: cur ? Theme.of(context).colorScheme.primary : past ? Colors.green : Colors.grey[300]),
              child: Icon(past ? Icons.check : cur ? Icons.my_location : Icons.circle,
                  size: 10, color: (cur || past) ? Colors.white : Colors.grey),
            ),
            if (!last) Container(width: 2, height: 20, color: Colors.grey[300]),
          ])),
          const SizedBox(width: 6),
          Padding(padding: const EdgeInsets.only(top: 2),
            child: Text(path[i], style: TextStyle(fontSize: 12,
                fontWeight: cur ? FontWeight.bold : FontWeight.normal,
                color: cur ? Colors.black87 : past ? Colors.black38 : Colors.black54))),
        ]);
      }),
    ],
  );

  Widget _rssi(String id, int rssi) {
    final frac = ((rssi + 100) / 60).clamp(0.0, 1.0);
    final label = _ble.beaconNames[id] ?? id;
    final c = rssi >= -65 ? Colors.green : rssi >= -80 ? Colors.orange : Colors.red;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54), overflow: TextOverflow.ellipsis)),
        Expanded(child: LinearProgressIndicator(value: frac, backgroundColor: Colors.grey[200],
            color: c, minHeight: 8, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 8),
        SizedBox(width: 52, child: Text('$rssi dBm', style: const TextStyle(fontSize: 11, color: Colors.black45), textAlign: TextAlign.right)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BLE DEBUG SCREEN  — reads from ValueNotifiers, no setMethodCallHandler
// ══════════════════════════════════════════════════════════════════════════════

class BleDebugScreen extends StatefulWidget {
  final MethodChannel bleChannel;
  final ValueNotifier<BleZoneEvent> bleZoneNotifier;
  final ValueNotifier<int> surveyTickNotifier;
  final ValueNotifier<bool> permissionNotifier;

  const BleDebugScreen({
    super.key, required this.bleChannel, required this.bleZoneNotifier,
    required this.surveyTickNotifier, required this.permissionNotifier,
  });

  @override
  State<BleDebugScreen> createState() => _BleDebugState();
}

class _BleDebugState extends State<BleDebugScreen> {
  bool _scanning = false;
  String _status = 'Ready to scan';
  BleZoneEvent _event = BleZoneEvent.empty();
  bool _surveying = false;
  int _surveyCount = 0;
  String _surveyName = '';
  List<String> _zones = [];
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.bleZoneNotifier.addListener(_onZone);
    widget.surveyTickNotifier.addListener(_onTick);
    _loadZones();
  }

  @override
  void dispose() {
    widget.bleZoneNotifier.removeListener(_onZone);
    widget.surveyTickNotifier.removeListener(_onTick);
    _ctrl.dispose();
    super.dispose();
  }

  void _onZone() { if (mounted) setState(() { _event = widget.bleZoneNotifier.value; _status = 'Positioning active'; }); }
  void _onTick() { if (mounted) setState(() => _surveyCount = widget.surveyTickNotifier.value); }
  bool get _hasPerms => widget.permissionNotifier.value;

  Future<void> _startScan() async {
    try {
      final bool ok = await widget.bleChannel.invokeMethod('startScanning');
      if (ok) setState(() { _scanning = true; _status = 'Scanning for beacons…'; });
    } catch (e) { setState(() => _status = 'Error: $e'); }
  }

  Future<void> _stopScan() async {
    if (_surveying) await _cancelSurvey();
    try { await widget.bleChannel.invokeMethod('stopScanning'); } catch (_) {}
    setState(() { _scanning = false; _status = 'Scanning stopped'; });
  }

  Future<void> _startSurvey() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) { _snack('Enter a zone name first'); return; }
    try {
      await widget.bleChannel.invokeMethod('startSurvey', {'zoneName': name});
      setState(() { _surveying = true; _surveyCount = 0; _surveyName = name; _status = 'Recording "$name"…'; });
    } catch (e) { _snack('Error: $e'); }
  }

  Future<void> _stopSurvey() async {
    try {
      final String? saved = await widget.bleChannel.invokeMethod<String>('stopSurvey');
      setState(() { _surveying = false; _status = saved != null ? 'Saved "$saved"' : 'No data saved'; });
      if (saved != null) { _snack('Fingerprint saved for "$saved"'); _ctrl.clear(); await _loadZones(); }
    } catch (e) { _snack('Error: $e'); }
  }

  Future<void> _cancelSurvey() async {
    try { await widget.bleChannel.invokeMethod('cancelSurvey'); } catch (_) {}
    setState(() { _surveying = false; _status = 'Survey cancelled'; });
  }

  Future<void> _loadZones() async {
    try {
      final List<dynamic> z = await widget.bleChannel.invokeMethod('getSurveyedZones');
      setState(() => _zones = z.cast<String>());
    } catch (_) {}
  }

  Future<void> _deleteZone(String name) async {
    try { await widget.bleChannel.invokeMethod('deleteZone', {'zoneName': name}); await _loadZones(); _snack('Deleted "$name"'); }
    catch (e) { _snack('Error: $e'); }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('BLE Debug')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          Row(children: [
            Icon(_scanning ? Icons.bluetooth_searching : Icons.bluetooth,
                color: _scanning ? Colors.blue : Colors.grey),
            const SizedBox(width: 8),
            Expanded(child: Text(_status, style: const TextStyle(fontSize: 14))),
          ]),
          if (!_hasPerms) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => widget.bleChannel.invokeMethod('requestPermissions'),
              icon: const Icon(Icons.security), label: const Text('Grant Permissions'),
            ),
          ],
        ]))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: ElevatedButton.icon(onPressed: _hasPerms && !_scanning ? _startScan : null,
              icon: const Icon(Icons.play_arrow), label: const Text('Start Scanning'))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton.icon(onPressed: _scanning ? _stopScan : null,
              icon: const Icon(Icons.stop), label: const Text('Stop Scanning'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white))),
        ]),
        const SizedBox(height: 12),
        Card(
          color: _scanning ? Colors.blue[50] : Colors.grey[100],
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Column(children: [
              const Text('Detected Zone', style: TextStyle(fontSize: 12, color: Colors.black54, letterSpacing: 1.1)),
              const SizedBox(height: 6),
              Text(_event.zone, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                  color: _scanning ? Theme.of(context).colorScheme.primary : Colors.grey)),
              Text('${_event.beaconCount} beacon${_event.beaconCount == 1 ? '' : 's'} visible',
                  style: const TextStyle(fontSize: 12, color: Colors.black45)),
            ]),
          ),
        ),
        if (_event.scanVector.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('RSSI Scan Vector', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Card(child: Padding(padding: const EdgeInsets.all(10),
              child: Column(children: _event.scanVector.entries.map((e) => _rssiRow(e.key, e.value)).toList()))),
        ],
        const SizedBox(height: 12),
        const Divider(),
        const Text('Manual Survey', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl, enabled: !_surveying,
          decoration: const InputDecoration(labelText: 'Zone name', hintText: 'e.g. Corridor North…',
              border: OutlineInputBorder(), prefixIcon: Icon(Icons.label_outline), isDense: true),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 8),
        if (_surveying) Padding(padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12), const SizedBox(width: 6),
            Text('Recording "$_surveyName" — $_surveyCount samples',
                style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w500)),
          ]),
        ),
        Row(children: [
          Expanded(child: ElevatedButton.icon(onPressed: _scanning && !_surveying ? _startSurvey : null,
              icon: const Icon(Icons.fiber_manual_record), label: const Text('Record'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton.icon(onPressed: _surveying ? _stopSurvey : null,
              icon: const Icon(Icons.save), label: const Text('Stop & Save'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white))),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Saved Fingerprints', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Text('${_zones.length} zones', style: const TextStyle(fontSize: 12, color: Colors.black45)),
        ]),
        const SizedBox(height: 4),
        Expanded(
          child: _zones.isEmpty
              ? const Center(child: Text('No fingerprints yet.', style: TextStyle(color: Colors.black38)))
              : ListView.builder(
                  itemCount: _zones.length,
                  itemBuilder: (_, i) => Card(child: ListTile(
                    dense: true,
                    leading: const CircleAvatar(radius: 14, backgroundColor: Colors.orange,
                        child: Icon(Icons.wifi_tethering, color: Colors.white, size: 14)),
                    title: Text(_zones[i], style: const TextStyle(fontSize: 13)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      onPressed: () => _confirmDel(_zones[i]),
                    ),
                  )),
                ),
        ),
      ]),
    ),
  );

  Widget _rssiRow(String id, int rssi) {
    final frac = ((rssi + 100) / 60).clamp(0.0, 1.0);
    final label = _event.beaconNames[id] ?? id;
    final c = rssi >= -65 ? Colors.green : rssi >= -80 ? Colors.orange : Colors.red;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        Row(children: [
          Expanded(child: LinearProgressIndicator(value: frac, backgroundColor: Colors.grey[200],
              color: c, minHeight: 8, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 8),
          Text('$rssi dBm', style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ]),
      ]),
    );
  }

  void _confirmDel(String name) => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Delete Fingerprint'),
      content: Text('Delete "$name"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () { Navigator.pop(context); _deleteZone(name); },
            style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
      ],
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// COMPASS ARROW PAINTER
// ══════════════════════════════════════════════════════════════════════════════

class _ArrowPainter extends CustomPainter {
  final double angle;
  final Color color;
  const _ArrowPainter({required this.angle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    canvas.drawCircle(c, r, Paint()..color = color.withOpacity(0.2)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    final tip = Offset(c.dx + r * 0.65 * sin(angle), c.dy - r * 0.65 * cos(angle));
    canvas.drawLine(c, tip, Paint()..color = color..strokeWidth = 3..strokeCap = StrokeCap.round);
    const hl = 9.0, ha = 0.4;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - hl * sin(angle - ha), tip.dy + hl * cos(angle - ha))
        ..lineTo(tip.dx - hl * sin(angle + ha), tip.dy + hl * cos(angle + ha))
        ..close(),
      Paint()..color = color..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.angle != angle || old.color != color;
}
