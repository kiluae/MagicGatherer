import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/splash_provider.dart';
import '../services/scryfall_repository.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) => _runSync());
  }

  Future<void> _runSync() async {
    final splash = context.read<SplashProvider>();
    await ScryfallRepository.syncDatabase(splash.setProgress);
    if (mounted) {
      _controller.stop();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SplashProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Transparent PNG spinner — no box, no decoration
            RotationTransition(
              turns: _controller,
              child: Image.asset(
                'assets/spinner.png',
                width: 100,
                color: Colors.white,
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (c, e, s) =>
                    const Icon(Icons.refresh, color: Colors.white, size: 60),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'MagicGatherer',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                provider.progressText,
                key: ValueKey(provider.progressText),
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
