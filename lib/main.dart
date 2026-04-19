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
      title: 'FlyFeet - Grid_Ai',
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

        if (!extended) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: CircleAvatar(
              radius: 25,
              backgroundColor: colorScheme.primary,
              backgroundImage: athlete!.profile.isNotEmpty ? MemoryImage(athlete!.profile) : null,
              child: athlete!.profile.isEmpty ? const Icon(Icons.person, size: 40) : null,
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.amber.shade700,
                const Color(0xFF2C2C2C),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.amber.shade300.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar and Overall Score Row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 65,
                    height: 65,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      image: athlete!.profile.isNotEmpty
                          ? DecorationImage(
                              image: MemoryImage(athlete!.profile),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: athlete!.profile.isEmpty
                        ? const Icon(Icons.person, color: Colors.white, size: 40)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        "70",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 34,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _getFlagIcon(athlete!.country),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Full Name
              Text(
                athlete!.name.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 1.1,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // Position
              Text(
                athlete!.position.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.amber.shade300,
                  fontWeight: FontWeight.bold,
                  fontSize: 9,
                  letterSpacing: 1.2,
                ),
              ),
              // Preferred Number
              Text(
                "${athlete!.preferredNumber}",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
              _buildSidebarGradientDivider(12),
              // Abilities
              _buildSidebarStatRow("Reaction", 78, "Agility", 72),
              const SizedBox(height: 8),
              _buildSidebarStatRow("Balance", 61, "Decision", 69),
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

  Widget _buildSidebarStatRow(String l1, int v1, String l2, int v2) {
    return Row(
      children: [
        Expanded(child: _buildSidebarStat(l1, v1)),
        const SizedBox(width: 8),
        Expanded(child: _buildSidebarStat(l2, v2)),
      ],
    );
  }

  Widget _buildSidebarStat(String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 7,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          "$value",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _getFlagIcon(String country) {
    String emoji = "";
    switch (country.toLowerCase()) {
      case 'brazil':
        emoji = "🇧🇷";
        break;
      case 'usa':
      case 'united states':
        emoji = "🇺🇸";
        break;
      case 'italy':
        emoji = "🇮🇹";
        break;
      case 'germany':
        emoji = "🇩🇪";
        break;
      case 'spain':
        emoji = "🇪🇸";
        break;
      case 'argentina':
        emoji = "🇦🇷";
        break;
      case 'france':
        emoji = "🇫🇷";
        break;
      case 'portugal':
        emoji = "🇵🇹";
        break;
      default:
        return const Icon(Icons.public, color: Colors.white24, size: 14);
    }
    return Text(
      emoji,
      style: const TextStyle(fontSize: 16),
    );
  }

  Widget _buildSidebarGradientDivider(double height) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: height / 2),
      height: 1.5,
      width: 150,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            Colors.amber.shade300.withOpacity(0.5),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}
