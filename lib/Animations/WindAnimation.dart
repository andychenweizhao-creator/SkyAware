import 'package:flutter/material.dart';

class WindAnimation{

  late AnimationController _windAnimController;

  WindAnimation({required TickerProvider vsync}){
    _windAnimController = AnimationController(
      vsync: vsync,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  Listenable  controller(){
    return _windAnimController;
}

  double getvalue(){
    return _windAnimController.value;
  }

  void dispose(){
    _windAnimController.dispose();
  }
}
