import 'package:flutter/material.dart';
import 'package:nimbus/authenication/pages/login.dart';
import 'package:nimbus/authenication/pages/register_page.dart';

class LoginOrRegister extends StatefulWidget {
  const LoginOrRegister({super.key});

  @override
  State<LoginOrRegister> createState() => _LoginOrRegisterState();
}

class _LoginOrRegisterState extends State<LoginOrRegister> {
  bool showLoginPage = true;

  void togglePages() {
    setState(() {
      showLoginPage = !showLoginPage;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (showLoginPage) {
      return MyLogin(onTap: togglePages);
    }

    return MyRegister(onTap: togglePages);
  }
}
