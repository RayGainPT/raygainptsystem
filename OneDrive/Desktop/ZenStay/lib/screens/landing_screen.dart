import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ZenStay')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => context.go('/euroescape'),
          child: const Text('Open demo property /euroescape'),
        ),
      ),
    );
  }
}
