import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/dark_theme.dart';
import 'gather_screen.dart';
import 'commander_roller_screen.dart';
import 'deck_doctor_screen.dart';
import 'card_search_screen.dart';
import 'deck_builder_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // Shared state passed between screens
  List<Map<String, dynamic>> _pendingGatherCards = [];
  String _pendingCommanderName = '';

  void _sendToGather(List<Map<String, dynamic>> cards, String commanderName) {
    setState(() {
      _pendingGatherCards     = cards;
      _pendingCommanderName   = commanderName;
      _selectedIndex          = 0; // Switch to Gather tab
    });
  }

  void _sendToDoctor(String commanderName) {
    setState(() {
      _pendingCommanderName = commanderName;
      _selectedIndex        = 2; // Switch to Deck Doctor tab
    });
  }

  void _sendGatherFromDoctor(List<Map<String, dynamic>> cards, String commanderName) {
    setState(() {
      _pendingGatherCards   = cards;
      _pendingCommanderName = commanderName;
      _selectedIndex        = 0;
    });
  }

  late final List<_NavDestination> _destinations = [
    _NavDestination(Icons.auto_fix_high_outlined, Icons.auto_fix_high,
        'Gather', 'Gather your Magic'),
    _NavDestination(Icons.casino_outlined, Icons.casino,
        'Commander', 'Commander Roller'),
    _NavDestination(Icons.medical_services_outlined, Icons.medical_services,
        'Deck Doctor', 'Deck Doctor'),
    _NavDestination(Icons.search_outlined, Icons.search,
        'Search', 'Card Search'),
    _NavDestination(Icons.picture_as_pdf_outlined, Icons.picture_as_pdf,
        'Proxy', 'Proxy Builder'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // ── Navigation Rail ────────────────────────────────────────────────
          NavigationRail(
            extended: false,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            leading: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              child: Column(
                children: [
                  // App icon / logo
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: kAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.style, color: Colors.white, size: 24),
                  ),
                ],
              ),
            ),
            destinations: _destinations.map((d) => NavigationRailDestination(
              icon:         Icon(d.unselectedIcon),
              selectedIcon: Icon(d.selectedIcon),
              label:        Text(d.label),
            )).toList(),
          ),
          const VerticalDivider(thickness: 1, width: 1),

          // ── Screen area ────────────────────────────────────────────────────
          Expanded(
            child: _buildScreen(),
          ),
        ],
      ),
    );
  }

  Widget _buildScreen() {
    switch (_selectedIndex) {
      case 0:
        return GatherScreen(
          key: ValueKey(_pendingGatherCards.length + _pendingCommanderName.length),
          initialCards:     _pendingGatherCards,
          initialCommander: _pendingCommanderName,
          onClearPending: () => setState(() {
            _pendingGatherCards   = [];
            _pendingCommanderName = '';
          }),
        ).animate().fadeIn(duration: 180.ms);

      case 1:
        return CommanderRollerScreen(
          onSendToGather: _sendToGather,
          onSendToDoctor: _sendToDoctor,
        ).animate().fadeIn(duration: 180.ms);

      case 2:
        return DeckDoctorScreen(
          initialCommander: _pendingCommanderName,
          onSendToGather:   _sendGatherFromDoctor,
        ).animate().fadeIn(duration: 180.ms);

      case 3:
        return const CardSearchScreen().animate().fadeIn(duration: 180.ms);

      case 4:
      default:
        return const DeckBuilderScreen().animate().fadeIn(duration: 180.ms);
    }
  }
}

class _NavDestination {
  final IconData unselectedIcon;
  final IconData selectedIcon;
  final String label;
  final String tooltip;
  const _NavDestination(this.unselectedIcon, this.selectedIcon,
      this.label, this.tooltip);
}
