import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sidebarx/sidebarx.dart';
import 'screens/bluetooth_screen.dart';
import 'screens/me_screen.dart';
import 'screens/exercise_screen.dart'; // Import the new screen
import 'services/bluetooth_service.dart';
import 'services/database_service.dart';
import 'models/athlete.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  
  // Initialize Services
  AppBluetoothService().init();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlyFeet D-Mat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6D00),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.dark,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _controller = SidebarXController(selectedIndex: 0, extended: true);
  final _key = GlobalKey<ScaffoldState>();
  Athlete? _currentAthlete;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadAthlete();
  }

  Future<void> _loadAthlete() async {
    final athletes = await DatabaseService().getAthletes();
    if (athletes.isNotEmpty) {
      setState(() {
        _currentAthlete = athletes.first;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      key: _key,
      backgroundColor: const Color(0xFF121212), // Professional Dark Theme
      drawer: ExampleSidebarX(controller: _controller, athlete: _currentAthlete),
      body: Row(
        children: [
          if (!isSmallScreen) ExampleSidebarX(controller: _controller, athlete: _currentAthlete),
          Expanded(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                switch (_controller.selectedIndex) {
                  case 0:
                    return const Center(child: Text('Dashboard', style: TextStyle(color: Colors.white, fontSize: 40)));
                  case 1:
                    return const ExerciseScreen();
                  case 2:
                    return const BluetoothScreen();
                  case 3:
                    return MeScreen(athlete: _currentAthlete); // Show the MeScreen
                  default:
                    return const Center(child: Text('Page not found', style: TextStyle(color: Colors.white, fontSize: 40)));
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ExampleSidebarX extends StatelessWidget {
  const ExampleSidebarX({
    super.key, 
    required SidebarXController controller,
    this.athlete,
  }) : _controller = controller;

  final SidebarXController _controller;
  final Athlete? athlete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return SidebarX(
      controller: _controller,
      theme: SidebarXTheme(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF3D3D3D),
          borderRadius: BorderRadius.circular(20),
        ),
        hoverColor: colorScheme.primaryContainer.withOpacity(0.1),
        textStyle: const TextStyle(color: Colors.white),
        selectedTextStyle: TextStyle(color: colorScheme.primary),
        itemTextPadding: const EdgeInsets.only(left: 30),
        selectedItemTextPadding: const EdgeInsets.only(left: 30),
        selectedItemDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.primary.withOpacity(0.37)),
          gradient: LinearGradient(colors: [const Color(0xFF4A4A4A), colorScheme.primaryContainer.withOpacity(0.2)]),
        ),
        iconTheme: const IconThemeData(color: Colors.white, size: 20),
        selectedIconTheme: IconThemeData(color: colorScheme.primary, size: 20),
      ),
      extendedTheme: const SidebarXTheme(
        width: 210,
        decoration: BoxDecoration(
          color: Color(0xFF353535),
          borderRadius: BorderRadius.only(topRight: Radius.circular(20), bottomRight: Radius.circular(20)),
        ),
      ),
      headerBuilder: (context, extended) {
        if (athlete == null) {
          return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
        }

        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              CircleAvatar(
                radius: extended ? 45 : 25,
                backgroundColor: colorScheme.primary,
                backgroundImage: athlete!.profile.isNotEmpty ? MemoryImage(athlete!.profile) : null,
                child: athlete!.profile.isEmpty ? const Icon(Icons.person, size: 40) : null,
              ),
              if (extended) ...[
                const SizedBox(height: 12),
                Text(athlete!.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                Text(athlete!.position, style: TextStyle(color: colorScheme.primary, fontSize: 12)),
              ]
            ],
          ),
        );
      },
      items: const [
        SidebarXItem(icon: Icons.dashboard_outlined, label: 'Dashboard'),
        SidebarXItem(icon: Icons.fitness_center, label: 'Exercise'),
        SidebarXItem(icon: Icons.bluetooth, label: 'Device'),
        SidebarXItem(icon: Icons.person_outline, label: 'Me'),
      ],
    );
  }
}
