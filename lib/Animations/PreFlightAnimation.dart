import 'package:flutter/material.dart';

class PreFlightAnimation{
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  PreFlightAnimation({required TickerProvider vsync}){
    _controller = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad));
    }

  Animation<double> get fadeAnimation =>  _fadeAnimation;
  void start(){
    _controller.forward();
  }
  Animation<Offset> get slideAnimation =>  _slideAnimation;

  void dispose(){
    _controller.dispose();
  }
}




