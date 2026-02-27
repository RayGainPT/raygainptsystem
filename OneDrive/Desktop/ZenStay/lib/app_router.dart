import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/landing_page.dart';
import 'screens/booking_screen.dart';
import 'screens/owner_dashboard.dart';
import 'screens/login_screen.dart';
import 'screens/signup_page.dart';

class FirebaseAuthChangeNotifier extends ChangeNotifier {
  late final StreamSubscription<User?> _sub;
  FirebaseAuthChangeNotifier() {
    _sub = FirebaseAuth.instance
        .authStateChanges()
        .listen((_) => notifyListeners());
  }
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final firebaseAuthChangeNotifier = FirebaseAuthChangeNotifier();

final GoRouter appRouter = GoRouter(
  refreshListenable: firebaseAuthChangeNotifier,
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const LandingPage(),
    ),
    // Static and more-specific routes first so they don't get captured by '/:slug'
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/signup',
      builder: (context, state) => const SignupPage(),
    ),
    GoRoute(
      path: '/dashboard',
      redirect: (context, state) => '/dashboard/euroescape',
    ),
    GoRoute(
      path: '/owner',
      redirect: (context, state) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return '/login';
        return null;
      },
      builder: (context, state) => const OwnerDashboard(),
    ),
    GoRoute(
      path: '/dashboard/:slug',
      redirect: (context, state) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return '/login';
        return null;
      },
      builder: (context, state) {
        final slug = state.pathParameters['slug'] ?? '';
        return OwnerDashboard(slug: slug);
      },
    ),
    // Keep the catch-all slug route last so named routes take precedence
    GoRoute(
      path: '/:slug',
      builder: (context, state) {
        final slug = state.pathParameters['slug'] ?? '';
        return BookingScreen(slug: slug);
      },
    ),
  ],
  errorBuilder: (context, state) => const Scaffold(
    body: Center(child: Text('Page not found')),
  ),
);
