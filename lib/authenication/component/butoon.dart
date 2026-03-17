import 'package:flutter/material.dart';

class myButton extends StatelessWidget{
 final Function ()? onTap;
 final String text;
 
  const myButton({super.key,required this.onTap,required this.text});
  @override
  Widget build(BuildContext context){
    return GestureDetector(
      onTap:onTap,
      child: Container(
        padding: EdgeInsets.all(25),
        margin: EdgeInsets.symmetric(horizontal:25.0),
        decoration:BoxDecoration(color: const Color.fromARGB(255, 236, 234, 234),
        borderRadius: BorderRadius.circular(20)),
        
        child:Center(child:Text(
          text,
          style: TextStyle(color: const Color.fromARGB(255, 0, 0, 0),fontSize:25,fontFamily: 'Helvetica ',fontWeight: FontWeight(1000)),
          ),
          ),
      ),
    );
 
 
 
  }
}
