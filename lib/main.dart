import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/map_scene.dart';
import 'welcome/welcome_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const BpnhsApp());
}

class BpnhsApp extends StatelessWidget {
  const BpnhsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SAFEROUTE',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF12345A),
        useMaterial3: true,
      ),
      home: const MapLoaderScreen(),
    );
  }
}

class MapLoaderScreen extends StatefulWidget {
  const MapLoaderScreen({super.key});

  @override
  State<MapLoaderScreen> createState() => _MapLoaderScreenState();
}

class _MapLoaderScreenState extends State<MapLoaderScreen> {
  MapScene? _scene;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMap();
    });
  }

  Future<void> _loadMap() async {
    try {
      final bundle = DefaultAssetBundle.of(context);
      final scene = await MapScene.loadFromAssets(
        bundle,
        'assets/map_workspace.json',
      );
      if (mounted) {
        setState(() {
          _scene = scene;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load map: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadMap, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_scene == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading map...'),
            ],
          ),
        ),
      );
    }

    return WelcomeScreen(scene: _scene!);
  }
}
