import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(const WayFindApp());
}

// ══════════════════════════════════════════════════════════════════════════════
// MODELS
// ══════════════════════════════════════════════════════════════════════════════

class MapNode {
  final String name;
  final int x;
  final int y;

  const MapNode({required this.name, required this.x, required this.y});

  Map<String, dynamic> toJson() => {'name': name, 'x': x, 'y': y};

  factory MapNode.fromJson(Map<String, dynamic> j) =>
      MapNode(name: j['name'] as String, x: j['x'] as int, y: j['y'] as int);

  @override
  bool operator ==(Object other) => other is MapNode && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

class MapEdge {
  final String from;
  final String to;

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
        edges: (j['edges'] as List).map((e) => MapEdge.fromJson(e)).toList(),
      );

  factory FloorMap.empty() => const FloorMap(nodes: [], edges: []);

  MapNode? nodeByName(String name) {
    try {
      return nodes.firstWhere((n) => n.name == name);
    } catch (_) {
      return null;
    }
  }

  List<String> neighborsOf(String name) {
    final result = <String>[];
    for (final e in edges) {
      if (e.from == name) result.add(e.to);
      if (e.to == name) result.add(e.from);
    }
    return result;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PATHFINDING  (BFS)
// ══════════════════════════════════════════════════════════════════════════════

class Pathfinder {
  static List<String>? findPath(FloorMap map, String start, String end) {
    if (start == end) return [start];
    final visited = <String>{start};
    final queue = <List<String>>[[start]];
    while (queue.isNotEmpty) {
      final path = queue.removeAt(0);
      final current = path.last;
      for (final neighbor in map.neighborsOf(current)) {
        if (neighbor == end) return [...path, neighbor];
        if (!visited.contains(neighbor)) {
          visited.add(neighbor);
          queue.add([...path, neighbor]);
        }
      }
    }
    return null;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DIRECTION HELPERS
// ══════════════════════════════════════════════════════════════════════════════
// Convention: 0° = North = (0,1) | 90° = East = (1,0)
//            180° = South = (0,-1) | 270° = West = (-1,0)

double vectorToCompassDegrees(int dx, int dy) {
  final rad = atan2(dx.toDouble(), dy.toDouble());
  return (rad * 180 / pi + 360) % 360;
}

double angleDiff(double target, double current) {
  double diff = (target - current + 360) % 360;
  if (diff > 180) diff -= 360;
  return diff;
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
// PERSISTENT STORAGE
// ══════════════════════════════════════════════════════════════════════════════

class MapStorage {
  static const _channel = MethodChannel('com.example.wayfind/nav');

  static Future<void> saveMap(FloorMap map) async {
    await _channel.invokeMethod('saveMap', jsonEncode(map.toJson()));
  }

  static Future<FloorMap> loadMap() async {
    try {
      final String? data = await _channel.invokeMethod<String>('loadMap');
      if (data == null || data.isEmpty) return FloorMap.empty();
      return FloorMap.fromJson(jsonDecode(data));
    } catch (_) {
      return FloorMap.empty();
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// APP ROOT
// ══════════════════════════════════════════════════════════════════════════════

class WayFindApp extends StatelessWidget {
  const WayFindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WayFind',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HOME SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  FloorMap _map = FloorMap.empty();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMap();
  }

  Future<void> _loadMap() async {
    final m = await MapStorage.loadMap();
    setState(() {
      _map = m;
      _loading = false;
    });
  }

  Future<void> _updateMap(FloorMap updated) async {
    await MapStorage.saveMap(updated);
    setState(() => _map = updated);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          MapEditorScreen(map: _map, onMapChanged: _updateMap),
          NavigationScreen(map: _map),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map Editor',
          ),
          NavigationDestination(
            icon: Icon(Icons.navigation_outlined),
            selectedIcon: Icon(Icons.navigation),
            label: 'Navigate',
          ),
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

  const MapEditorScreen(
      {super.key, required this.map, required this.onMapChanged});

  @override
  State<MapEditorScreen> createState() => _MapEditorScreenState();
}

class _MapEditorScreenState extends State<MapEditorScreen> {
  final _nameController = TextEditingController();
  String? _selectedAdjacentNode;
  String? _selectedDirection;

  static const _directionOffsets = {
    'North': (0, 1),
    'South': (0, -1),
    'East':  (1, 0),
    'West':  (-1, 0),
  };

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _showSnackBar(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _addNode() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) { _showSnackBar('Enter a location name first'); return; }
    if (widget.map.nodeByName(name) != null) {
      _showSnackBar('"$name" already exists'); return;
    }

    int x = 0, y = 0;
    final newEdges = List<MapEdge>.from(widget.map.edges);

    if (widget.map.nodes.isNotEmpty) {
      if (_selectedAdjacentNode == null || _selectedDirection == null) {
        _showSnackBar('Select an adjacent node and direction'); return;
      }
      final anchor = widget.map.nodeByName(_selectedAdjacentNode!)!;
      final offset = _directionOffsets[_selectedDirection!]!;
      x = anchor.x + offset.$1;
      y = anchor.y + offset.$2;

      if (widget.map.nodes.any((n) => n.x == x && n.y == y)) {
        _showSnackBar('A location already exists at that position'); return;
      }
      newEdges.add(MapEdge(from: _selectedAdjacentNode!, to: name));
    }

    await widget.onMapChanged(FloorMap(
      nodes: [...widget.map.nodes, MapNode(name: name, x: x, y: y)],
      edges: newEdges,
    ));

    setState(() {
      _nameController.clear();
      _selectedAdjacentNode = null;
      _selectedDirection = null;
    });
    _showSnackBar('Added "$name"');
  }

  Future<void> _deleteNode(String name) async {
    await widget.onMapChanged(FloorMap(
      nodes: widget.map.nodes.where((n) => n.name != name).toList(),
      edges: widget.map.edges
          .where((e) => e.from != name && e.to != name)
          .toList(),
    ));
    _showSnackBar('Deleted "$name"');
  }

  Future<void> _clearMap() async {
    await widget.onMapChanged(FloorMap.empty());
    setState(() {
      _selectedAdjacentNode = null;
      _selectedDirection = null;
    });
    _showSnackBar('Map cleared');
  }

  @override
  Widget build(BuildContext context) {
    final nodes = widget.map.nodes;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.inversePrimary,
        title: const Text('WayFind'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: _showInfoDialog,
          ),
          if (nodes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear entire map',
              onPressed: () => _confirmClear(context),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Mini map ──────────────────────────────────────────────────────
            if (nodes.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text('Floor Map',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                                letterSpacing: 0.5)),
                      ),
                      SizedBox(
                        height: 160,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _MapVisualizer(map: widget.map),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Add node form ─────────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Add New Location',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Location name',
                        hintText: 'e.g. Bottom Corridor, Room A…',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      textCapitalization: TextCapitalization.words,
                      onSubmitted: (_) => _addNode(),
                    ),
                    if (nodes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedAdjacentNode,
                            decoration: const InputDecoration(
                              labelText: 'Adjacent to',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.link),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 12),
                            ),
                            items: nodes
                                .map((n) => DropdownMenuItem(
                                    value: n.name,
                                    child: Text(n.name,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            const TextStyle(fontSize: 13))))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedAdjacentNode = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedDirection,
                            decoration: const InputDecoration(
                              labelText: 'Direction',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.explore_outlined),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 12),
                            ),
                            items: ['North', 'South', 'East', 'West']
                                .map((d) => DropdownMenuItem(
                                    value: d,
                                    child: Row(children: [
                                      Text(_dirIcon(d)),
                                      const SizedBox(width: 6),
                                      Text(d,
                                          style: const TextStyle(
                                              fontSize: 13)),
                                    ])))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedDirection = v),
                          ),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _addNode,
                        icon: const Icon(Icons.add_location_alt),
                        label: Text(nodes.isEmpty
                            ? 'Add First Location'
                            : 'Add Location'),
                      ),
                    ),
                    if (nodes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          '⚠ First location is set as the map origin (0, 0).',
                          style: TextStyle(
                              fontSize: 12, color: Colors.deepOrange),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Saved locations header ────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Saved Locations',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                Text(
                    '${nodes.length} location${nodes.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black45)),
              ],
            ),
            const SizedBox(height: 6),

            // ── Node list ─────────────────────────────────────────────────────
            Expanded(
              child: nodes.isEmpty
                  ? const Center(
                      child: Text(
                        'No locations added yet.\nAdd your first location above.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black38),
                      ),
                    )
                  : ListView.builder(
                      itemCount: nodes.length,
                      itemBuilder: (_, i) {
                        final node = nodes[i];
                        final neighbors =
                            widget.map.neighborsOf(node.name);
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primary,
                              child: Text(
                                '${node.x},${node.y}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(node.name),
                            subtitle: Text(
                              neighbors.isEmpty
                                  ? 'No connections'
                                  : 'Connected: ${neighbors.join(", ")}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black45),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              tooltip: 'Delete location',
                              onPressed: () =>
                                  _confirmDeleteNode(context, node.name),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _dirIcon(String dir) {
    switch (dir) {
      case 'North': return '↑';
      case 'South': return '↓';
      case 'East':  return '→';
      case 'West':  return '←';
      default:      return '?';
    }
  }

  void _confirmDeleteNode(BuildContext ctx, String name) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete Location'),
        content: Text('Delete "$name" and all its connections?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteNode(name);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Clear Map'),
        content: const Text(
            'Delete all locations and connections? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearMap();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('About WayFind'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('WayFind — Indoor Navigation',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text(
                  'Navigate between locations using a custom floor map and your phone\'s compass.'),
              SizedBox(height: 12),
              Text('Map Editor:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('• Add your first location — it becomes the map origin (0,0)\n'
                  '• Each new location is placed relative to an existing one\n'
                  '• Choose the adjacent node and the direction to it\n'
                  '• The map is saved persistently on-device'),
              SizedBox(height: 12),
              Text('Navigate:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('• Pick source and destination\n'
                  '• Follow turn-by-turn compass guidance\n'
                  '• Direction updates every 3 seconds\n'
                  '• Tap "I\'ve Arrived" to advance each step'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MAP VISUALIZER
// ══════════════════════════════════════════════════════════════════════════════

class _MapVisualizer extends StatelessWidget {
  final FloorMap map;
  const _MapVisualizer({required this.map});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MapPainter(map, Theme.of(context).colorScheme.primary),
      child: const SizedBox.expand(),
    );
  }
}

class _MapPainter extends CustomPainter {
  final FloorMap map;
  final Color primaryColor;

  _MapPainter(this.map, this.primaryColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (map.nodes.isEmpty) return;

    canvas.drawRect(
        Offset.zero & size, Paint()..color = Colors.blue.shade50);

    final nodePaint = Paint()..color = primaryColor;
    final edgePaint = Paint()
      ..color = primaryColor.withOpacity(0.4)
      ..strokeWidth = 2;

    final xs = map.nodes.map((n) => n.x.toDouble()).toList();
    final ys = map.nodes.map((n) => n.y.toDouble()).toList();
    final minX = xs.reduce(min);
    final maxX = xs.reduce(max);
    final minY = ys.reduce(min);
    final maxY = ys.reduce(max);

    const padding = 28.0;
    final rangeX = (maxX - minX).clamp(1, double.infinity);
    final rangeY = (maxY - minY).clamp(1, double.infinity);
    final scaleX = (size.width - padding * 2) / rangeX;
    final scaleY = (size.height - padding * 2) / rangeY;
    final scale = min(scaleX, scaleY);

    Offset toScreen(int x, int y) {
      final sx = padding +
          (x - minX) * scale +
          (size.width - padding * 2 - rangeX * scale) / 2;
      final sy = size.height -
          padding -
          (y - minY) * scale -
          (size.height - padding * 2 - rangeY * scale) / 2;
      return Offset(sx, sy);
    }

    for (final edge in map.edges) {
      final from = map.nodeByName(edge.from);
      final to = map.nodeByName(edge.to);
      if (from != null && to != null) {
        canvas.drawLine(
            toScreen(from.x, from.y), toScreen(to.x, to.y), edgePaint);
      }
    }

    for (final node in map.nodes) {
      final pos = toScreen(node.x, node.y);
      canvas.drawCircle(pos, 8, nodePaint);
      final tp = TextPainter(
        text: TextSpan(
            text: node.name,
            style: const TextStyle(
                color: Colors.black87,
                fontSize: 9,
                fontWeight: FontWeight.w500)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 80);
      tp.paint(canvas, pos.translate(-tp.width / 2, 10));
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => true;
}

// ══════════════════════════════════════════════════════════════════════════════
// NAVIGATION SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class NavigationScreen extends StatefulWidget {
  final FloorMap map;
  const NavigationScreen({super.key, required this.map});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  static const _channel = MethodChannel('com.example.wayfind/nav');

  // ── Route ─────────────────────────────────────────────────────────────────
  String? _source;
  String? _destination;
  List<String>? _path;
  int _step = 0;

  // ── Compass ───────────────────────────────────────────────────────────────
  double _compassHeading = 0.0;
  String _turnInstruction = '';
  double _targetHeading = 0.0;
  bool _compassActive = false;

  // ── TTS (flutter_tts package) ─────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  String _lastSpokenInstruction = '';

  // ── STT (native Android via MethodChannel — no package needed) ────────────
  bool _isListening = false;
  bool _listeningForSource = false;

  // ── BLE zone ──────────────────────────────────────────────────────────────
  String _currentBleZone = '—';

  // ═════════════════════════════════════════════════════════════════════════
  // Init / Dispose
  // ═════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _setupChannel();
    _startCompass();
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _speakIfNew(String text) async {
    if (text.isEmpty || text == _lastSpokenInstruction) return;
    _lastSpokenInstruction = text;
    await _tts.stop();
    await _tts.speak(text);
  }

  void _setupChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {

        case 'onCompassUpdate':
          final double heading = (call.arguments as num).toDouble();
          setState(() {
            _compassHeading = heading;
            if (_compassActive) _updateTurnInstruction();
          });
          break;

        case 'onZoneData':
          final data = jsonDecode(call.arguments as String);
          setState(() => _currentBleZone = data['zone'] as String? ?? '—');
          break;

        // ── Result from Android native speech dialog ──────────────────────
        case 'onSpeechResult':
          final spoken =
              ((call.arguments as String?) ?? '').toLowerCase().trim();
          setState(() => _isListening = false);
          if (spoken.isNotEmpty) {
            _matchLocationFromVoice(spoken, isSource: _listeningForSource);
          }
          break;
      }
    });
  }

  Future<void> _startCompass() async {
    try {
      await _channel.invokeMethod('startCompass');
    } catch (_) {}
  }

  @override
  void dispose() {
    _channel.invokeMethod('stopCompass').catchError((_) {});
    _tts.stop();
    super.dispose();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Navigation logic
  // ═════════════════════════════════════════════════════════════════════════

  void _computeRoute() {
    if (_source == null || _destination == null) return;
    if (_source == _destination) {
      _showSnackBar('Source and destination are the same');
      return;
    }
    final path = Pathfinder.findPath(widget.map, _source!, _destination!);
    if (path == null) {
      _showSnackBar('No path found between selected locations');
      setState(() {
        _path = null;
        _step = 0;
      });
      return;
    }
    setState(() {
      _path = path;
      _step = 0;
      _compassActive = true;
      _lastSpokenInstruction = '';
      _updateTurnInstruction();
    });
    final nextNode = path.length > 1 ? path[1] : path[0];
    _speakIfNew("Starting navigation. Head to $nextNode.");
  }

  void _updateTurnInstruction() {
    if (_path == null || _step >= _path!.length - 1) {
      setState(() => _turnInstruction = '');
      return;
    }
    final current = widget.map.nodeByName(_path![_step]);
    final next = widget.map.nodeByName(_path![_step + 1]);
    if (current == null || next == null) return;

    final dx = next.x - current.x;
    final dy = next.y - current.y;
    _targetHeading = vectorToCompassDegrees(dx, dy);

    final diff = angleDiff(_targetHeading, _compassHeading);
    final newInstruction = turnInstruction(diff);
    setState(() => _turnInstruction = newInstruction);
    if (_compassActive) _speakIfNew(newInstruction);
  }

  void _advanceStep() {
    if (_path == null || _step >= _path!.length - 1) return;
    final nextStep = _step + 1;
    final isLastStep = nextStep == _path!.length - 1;
    setState(() {
      _step++;
      _lastSpokenInstruction = '';
      _updateTurnInstruction();
    });
    if (isLastStep) {
      _speakIfNew(
          "You have arrived at ${_path!.last}. Navigation complete.");
    } else {
      _speakIfNew("Arrived. Now head to ${_path![nextStep + 1]}.");
    }
  }

  void _endNavigation() {
    setState(() {
      _path = null;
      _step = 0;
      _compassActive = false;
      _turnInstruction = '';
      _source = null;
      _destination = null;
    });
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Native STT — opens Android Google speech dialog via MethodChannel
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _listenForLocation({required bool isSource}) async {
    // Speak the prompt first, then open the native dialog
    setState(() {
      _isListening = true;
      _listeningForSource = isSource;
    });

    await _tts.stop();
    await _tts.speak(isSource
        ? "Which location are you starting from?"
        : "Which location do you want to go to?");

    // Wait for TTS to finish before opening mic dialog
    await Future.delayed(const Duration(milliseconds: 2500));

    try {
      await _channel.invokeMethod(
        'startSpeechInput',
        isSource ? "Starting location?" : "Destination?",
      );
      // Result comes back via onSpeechResult in _setupChannel
    } catch (e) {
      setState(() => _isListening = false);
      _showSnackBar('Speech input not available on this device');
    }
  }

  void _matchLocationFromVoice(String spoken, {required bool isSource}) {
    final nodes = widget.map.nodes;
    String? matched;
    for (final node in nodes) {
      if (spoken.contains(node.name.toLowerCase())) {
        matched = node.name;
        break;
      }
    }
    if (matched != null) {
      setState(() {
        if (isSource) {
          _source = matched;
        } else {
          _destination = matched;
        }
      });
      _speakIfNew(
          "${isSource ? 'Starting from' : 'Going to'} $matched.");
    } else {
      _speakIfNew(
          "Sorry, I did not recognize that location. Please try again.");
    }
  }

  void _showSnackBar(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  // ═════════════════════════════════════════════════════════════════════════
  // Build
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final nodes = widget.map.nodes;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('WayFind'),
        actions: [
          if (_path != null)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'End navigation',
              onPressed: _endNavigation,
            ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () {},
          ),
        ],
      ),
      body: nodes.isEmpty
          ? _buildEmptyState()
          : _path == null
              ? _buildRoutePicker(nodes)
              : _buildActiveNavigation(),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 64, color: Colors.black26),
              SizedBox(height: 16),
              Text('No map loaded.',
                  style: TextStyle(fontSize: 18, color: Colors.black54)),
              SizedBox(height: 6),
              Text(
                'Go to the Map Editor tab and add locations first.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black38),
              ),
            ],
          ),
        ),
      );

  // ── Route picker ───────────────────────────────────────────────────────────

  Widget _buildRoutePicker(List<MapNode> nodes) {
    final items = nodes
        .map((n) => DropdownMenuItem(value: n.name, child: Text(n.name)))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // BLE zone status
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.bluetooth,
                    color: _currentBleZone == '—'
                        ? Colors.grey
                        : Colors.blue),
                const SizedBox(width: 8),
                const Text('BLE Detected Zone:  ',
                    style:
                        TextStyle(fontSize: 14, color: Colors.black54)),
                Expanded(
                  child: Text(
                    _currentBleZone,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 16),

          // Route selection card
          Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Plan Your Route',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),

                  // ── FROM row with mic button ───────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _source,
                          decoration: const InputDecoration(
                            labelText: 'From',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.trip_origin),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          items: items,
                          onChanged: (v) =>
                              setState(() => _source = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: (_isListening && _listeningForSource)
                              ? Colors.red[50]
                              : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: (_isListening && _listeningForSource)
                                ? Colors.red
                                : Colors.blue,
                          ),
                        ),
                        child: IconButton(
                          icon: Icon(
                            (_isListening && _listeningForSource)
                                ? Icons.mic
                                : Icons.mic_none,
                            color: (_isListening && _listeningForSource)
                                ? Colors.red
                                : Colors.blue,
                          ),
                          tooltip: 'Speak starting location',
                          onPressed: () =>
                              _listenForLocation(isSource: true),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  const Center(
                    child: Icon(Icons.arrow_downward,
                        color: Colors.blue, size: 28),
                  ),
                  const SizedBox(height: 8),

                  // ── TO row with mic button ─────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _destination,
                          decoration: const InputDecoration(
                            labelText: 'To',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.location_on),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          items: items,
                          onChanged: (v) =>
                              setState(() => _destination = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: (_isListening && !_listeningForSource)
                              ? Colors.red[50]
                              : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: (_isListening && !_listeningForSource)
                                ? Colors.red
                                : Colors.blue,
                          ),
                        ),
                        child: IconButton(
                          icon: Icon(
                            (_isListening && !_listeningForSource)
                                ? Icons.mic
                                : Icons.mic_none,
                            color: (_isListening && !_listeningForSource)
                                ? Colors.red
                                : Colors.blue,
                          ),
                          tooltip: 'Speak destination',
                          onPressed: () =>
                              _listenForLocation(isSource: false),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _source != null && _destination != null
                              ? _computeRoute
                              : null,
                      icon: const Icon(Icons.navigation),
                      label: const Text('Start Navigation',
                          style: TextStyle(fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Active navigation ──────────────────────────────────────────────────────

  Widget _buildActiveNavigation() {
    final path = _path!;
    final isLastStep = _step >= path.length - 1;
    final currentName = path[_step];
    final nextName = isLastStep ? null : path[_step + 1];

    String dirLabel = '';
    if (!isLastStep) {
      final cur = widget.map.nodeByName(currentName);
      final nxt = widget.map.nodeByName(nextName!);
      if (cur != null && nxt != null) {
        dirLabel = directionLabel(nxt.x - cur.x, nxt.y - cur.y);
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildProgressCard(path),
          const SizedBox(height: 12),

          // Current location
          Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: 20, horizontal: 16),
              child: Column(children: [
                const Text('Current Location',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        letterSpacing: 1.1)),
                const SizedBox(height: 6),
                Text(
                  currentName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color:
                          Theme.of(context).colorScheme.primary),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          if (!isLastStep) ...[
            _buildDirectionCard(nextName!, dirLabel),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _advanceStep,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text("I've Arrived — Next Step",
                  style: TextStyle(fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            Card(
              color: Colors.green[50],
              child: const Padding(
                padding: EdgeInsets.symmetric(
                    vertical: 24, horizontal: 16),
                child: Column(children: [
                  Icon(Icons.check_circle,
                      color: Colors.green, size: 56),
                  SizedBox(height: 10),
                  Text('Destination Reached!',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _endNavigation,
              icon: const Icon(Icons.replay),
              label: const Text('Plan New Route',
                  style: TextStyle(fontSize: 15)),
              style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 12),
          ],

          Expanded(child: _buildRouteOverview(path)),
        ],
      ),
    );
  }

  Widget _buildProgressCard(List<String> path) {
    final progress =
        path.length <= 1 ? 1.0 : _step / (path.length - 1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Step ${_step + 1} of ${path.length}',
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black54)),
                Text(
                    '${(progress * 100).toStringAsFixed(0)}% complete',
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.grey[200],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectionCard(String nextName, String dirLabel) {
    final diff = angleDiff(_targetHeading, _compassHeading);
    final isAligned = diff.abs() < 15;

    return Card(
      color: isAligned ? Colors.green[50] : Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.arrow_forward,
                  color: isAligned ? Colors.green : Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Head to',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            letterSpacing: 1)),
                    Text(nextName,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              SizedBox(
                width: 64,
                height: 64,
                child: CustomPaint(
                  painter: _ArrowPainter(
                    angle: ((_targetHeading - _compassHeading) *
                        pi /
                        180),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ]),

            const Divider(height: 20),

            Row(children: [
              const Icon(Icons.explore,
                  color: Colors.black38, size: 18),
              const SizedBox(width: 6),
              Text(
                  'Face $dirLabel  •  ${_targetHeading.toStringAsFixed(0)}°',
                  style: const TextStyle(
                      fontSize: 13, color: Colors.black54)),
            ]),
            const SizedBox(height: 8),

            Row(children: [
              Icon(
                isAligned
                    ? Icons.check_circle
                    : Icons.rotate_right,
                color: isAligned ? Colors.green : Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _turnInstruction.isEmpty
                    ? 'Calculating…'
                    : _turnInstruction,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isAligned
                      ? Colors.green[700]
                      : Colors.orange[800],
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              'Your heading: ${_compassHeading.toStringAsFixed(0)}°',
              style: const TextStyle(
                  fontSize: 11, color: Colors.black38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteOverview(List<String> path) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Route Overview',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            itemCount: path.length,
            itemBuilder: (_, i) {
              final isPast = i < _step;
              final isCurrent = i == _step;
              final isLast = i == path.length - 1;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Column(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCurrent
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                : isPast
                                    ? Colors.green
                                    : Colors.grey[300],
                          ),
                          child: Icon(
                            isPast
                                ? Icons.check
                                : isCurrent
                                    ? Icons.my_location
                                    : Icons.circle,
                            size: 11,
                            color: (isCurrent || isPast)
                                ? Colors.white
                                : Colors.grey,
                          ),
                        ),
                        if (!isLast)
                          Container(
                              width: 2,
                              height: 22,
                              color: Colors.grey[300]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      path[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isCurrent
                            ? Colors.black87
                            : isPast
                                ? Colors.black38
                                : Colors.black54,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
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
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withOpacity(0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    final tip = Offset(
      center.dx + radius * 0.65 * sin(angle),
      center.dy - radius * 0.65 * cos(angle),
    );
    canvas.drawLine(
        center,
        tip,
        Paint()
          ..color = color
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);

    const headLen = 9.0;
    const headAngle = 0.4;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(
          tip.dx - headLen * sin(angle - headAngle),
          tip.dy + headLen * cos(angle - headAngle),
        )
        ..lineTo(
          tip.dx - headLen * sin(angle + headAngle),
          tip.dy + headLen * cos(angle + headAngle),
        )
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.angle != angle || old.color != color;
}