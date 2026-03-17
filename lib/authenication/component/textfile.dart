import 'package:flutter/material.dart';

class myText extends StatelessWidget{
  final controller;
  final String hintText;
  final bool obscureText;
  const myText({
    super.key,
    required this.controller,
    required this.hintText,
    required this.obscureText,
    });
  @override
  Widget build(BuildContext context){
    return Padding(
                padding: EdgeInsets.symmetric(horizontal:25.0), 
                child: TextField(
                  controller:controller,
                  obscureText: obscureText,
                    style:TextStyle(color:Colors.black,fontFamily: 'Helvetica',fontSize: 16),
                    
                  decoration:InputDecoration(
                    enabledBorder: OutlineInputBorder(borderRadius:BorderRadius.circular(15),borderSide:BorderSide(color:const Color.fromARGB(255, 225, 221, 221))), 
                    focusedBorder: OutlineInputBorder(borderRadius:BorderRadius.circular(15),borderSide:BorderSide(color:Color.fromARGB(220, 96, 94, 94))),
                    fillColor: const Color.fromARGB(255, 232, 229, 229),
                    filled:true,
                    hintText: hintText,
                    hintStyle: TextStyle(color:Color.fromARGB(255, 62, 61, 61)),
                     
                  )
                ),
              );
  }
}