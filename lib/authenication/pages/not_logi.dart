import 'package:flutter/material.dart';

class notLogin extends StatefulWidget{
  const notLogin({super.key});

  @override
  State<notLogin> createState() => _notLoginState();
}

class _notLoginState extends State<notLogin> {
  @override
  Widget build(BuildContext context){
    return Scaffold(
      body: Center(
        child:Text('oops')
      ),
    );
  }
}