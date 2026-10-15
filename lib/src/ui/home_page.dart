import 'package:flutter/material.dart';

import '../audio/listen_controller.dart';
import 'listen_view.dart';
import 'tap_view.dart';

/// The two modes, switched with the navigation bar.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.listenController});

  final ListenController listenController;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _mode = 0;

  void _select(int mode) {
    // Leaving the listen mode releases the microphone.
    if (mode != 1) widget.listenController.stop();
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BPM Counter')),
      body: SafeArea(
        top: false,
        bottom: false,
        child: IndexedStack(
          index: _mode,
          children: [
            const TapView(),
            ListenView(controller: widget.listenController),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 68,
        selectedIndex: _mode,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.touch_app_outlined),
            selectedIcon: Icon(Icons.touch_app),
            label: 'Tap',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none),
            selectedIcon: Icon(Icons.mic),
            label: 'Listen',
          ),
        ],
      ),
    );
  }
}
