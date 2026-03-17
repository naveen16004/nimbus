import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:nimbus/authenication/pages/home.dart';
import 'package:nimbus/authenication/pages/login_or_register.dart';

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (BuildContext context, AsyncSnapshot<User?> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const HomePage();
        }

        return const LoginOrRegister();
      },
    );
  }
}

// Backward-compatible alias for previous naming.
class myPerm extends StatelessWidget {
  const myPerm({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthPage();
  }
}
