import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'focus_bus.dart';
import 'services/updater.dart';
import 'screens/map_screen.dart';
import 'screens/fields_screen.dart';
import 'screens/places_screen.dart';
import 'screens/tracks_screen.dart';
import 'screens/more_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    FlutterDownloader.registerCallback(downloadCallback);
    await FlutterDownloader.initialize(debug: false);
  } catch (_) {
    // 后台下载组件初始化失败不阻塞 app
  }
  runApp(const FieldMapApp());
}

@pragma('vm:entry-point')
void downloadCallback(String id, DownloadTaskStatus status, int progress) {
  // 进度由系统通知栏展示，这里无需处理
}

class FieldMapApp extends StatelessWidget {
  const FieldMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: MaterialApp(
        title: '地块管家',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2E7D32),
          ),
          useMaterial3: true,
        ),
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // 其他页请求定位地块/轨迹时，自动切到地图页
    FocusBus.req.addListener(() {
      if (mounted && FocusBus.req.value != null) {
        setState(() => _tab = 0);
      }
    });
    // 启动后自动检查更新（有新版本才弹窗）
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) Updater.checkAndPrompt(context, silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const MapScreen(),
      const FieldsScreen(),
      const PlacesScreen(),
      const TracksScreen(),
      const MoreScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: '地图'),
          NavigationDestination(icon: Icon(Icons.grass_outlined), selectedIcon: Icon(Icons.grass), label: '地块'),
          NavigationDestination(icon: Icon(Icons.place_outlined), selectedIcon: Icon(Icons.place), label: '地点'),
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: '轨迹'),
          NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more), label: '更多'),
        ],
      ),
    );
  }
}
