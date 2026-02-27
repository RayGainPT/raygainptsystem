import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'app_router.dart';
import 'utils/color_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ZenStayApp());
}

class ZenStayApp extends StatelessWidget {
  const ZenStayApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    // Listen for theme overrides in the `properties/euroescape` document.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('properties')
          .doc('euroescape')
          .snapshots(),
      builder: (context, snapshot) {
        Color primary = Colors.blue;
        Color secondary = Colors.teal;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          if (data != null) {
            final p = data['primaryColor'];
            final s = data['secondaryColor'];
            try {
              if (p is String && p.isNotEmpty) primary = ColorUtils.fromHex(p);
            } catch (_) {}
            try {
              if (s is String && s.isNotEmpty)
                secondary = ColorUtils.fromHex(s);
            } catch (_) {}
          }
        }

        final baseScheme = ColorScheme.fromSeed(seedColor: primary)
            .copyWith(primary: primary, secondary: secondary);

        final theme = ThemeData(
          useMaterial3: true,
          colorScheme: baseScheme,
          scaffoldBackgroundColor: const Color(0xFFF8F9FA),
          textTheme: GoogleFonts.interTextTheme(),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
          ),
        );

        return MaterialApp.router(
          title: 'ZenStay',
          routerConfig: appRouter,
          debugShowCheckedModeBanner: false,
          theme: theme,
        );
      },
    );
  }
}
