import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:nimbus/authenication/component/butoon.dart';
import 'package:nimbus/authenication/component/textfile.dart';

class MyRegister extends StatefulWidget {
  const MyRegister({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  State<MyRegister> createState() => _MyRegisterState();
}

class _MyRegisterState extends State<MyRegister> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> signUserUp() async {
    if (_passwordController.text.trim() != _confirmController.text.trim()) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? 'Sign up failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const SizedBox(height: 25),
                const Icon(
                  Icons.face,
                  color: Colors.white,
                  size: 100,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Set up your account',
                  style: TextStyle(
                    fontFamily: 'Helvetica',
                    fontSize: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                myText(
                  controller: _emailController,
                  hintText: 'Enter Email',
                  obscureText: false,
                ),
                const SizedBox(height: 20),
                myText(
                  controller: _passwordController,
                  hintText: 'Enter password',
                  obscureText: true,
                ),
                const SizedBox(height: 20),
                myText(
                  controller: _confirmController,
                  hintText: 'Confirm password',
                  obscureText: true,
                ),
                const SizedBox(height: 20),
                myButton(
                  text: 'Sign Up',
                  onTap: signUserUp,
                ),
                const SizedBox(height: 50),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text(
                      'Already a user?',
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: widget.onTap,
                      child: const Text(
                        'Sign in',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
