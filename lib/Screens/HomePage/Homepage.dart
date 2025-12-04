import 'package:flutter/material.dart';
import 'dart:ui';
import '../../Service/WeatherEngine.dart';
class HomePage extends StatefulWidget
{
  @override
  State<HomePage> createState(){
    return _Homepage();

  }
}
class _Homepage extends State<HomePage>
{
  Widget background = Container
    (
    decoration: const BoxDecoration
      (
      gradient: LinearGradient
        (
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0A84FF), Color(0xFF5E5CE6), Color(0xFF7D2AE8)],
      ),
    ),
  );
  Widget title = Row(
      children: [
        Container(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "SkyAware",
                style: TextStyle(
                  fontSize: 60,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                  foreground: Paint()
                    ..shader = const LinearGradient(
                      colors: [Color(0xFF66D1FF), Color(0xFF00FFA3)],
                    ).
                    createShader(const Rect.fromLTWH(0, 0, 300, 80)),
                  shadows: const [Shadow(color: Colors.black45, blurRadius: 18, offset: Offset(0, 6))],
                ),
              ),
              Text(
                "Aviation Intelligence System",
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.2
                ),
              )
            ],
          ),
        ),
        Container(
          margin: EdgeInsets.only(top: 24),
          child: Icon(
            Icons.flight,
            color: Colors.white,
            size: 60,
          ),
        )
      ]
  );
  Widget box(){
    return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        )
    );
  }


  @override
  Widget build(BuildContext context)
  {
    return Scaffold
      (
      // extendBodyBehindAppBar: true,
      // appBar: AppBar(
      //   title: Text("SkyAware"),
      //   backgroundColor: Colors.transparent,
      //   elevation: 0,
      //   flexibleSpace:
      //   Container
      //     (
      //     decoration: const BoxDecoration
      //       (
      //       gradient: LinearGradient
      //         (
      //         begin: Alignment.topLeft,
      //         end: Alignment.bottomRight,
      //         colors: [Color(0xFF0A84FF),Color(0xFF0A84FF)],
      //       ),
      //     ),
      //   ),
      // ),
      body: Stack
        (
        children:
        [
          background,
          Container(
            margin: const EdgeInsets.only(top: 40),
            child: Expanded(
              child: SingleChildScrollView(
                child:Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                        margin: const EdgeInsets.only(left: 20),
                        child: title
                    ),
                    const SizedBox(height: 30),
                    Container(
                      margin: const EdgeInsets.only(right: 40),
                      child: const Text(
                        "Flight Safety Index",
                        style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(right: 40, top: 0),
                      child: const Text(
                        "Real‑Time VFR Risk Model",
                        style: TextStyle(fontSize: 19, color: Color(0xFFB8C4D4), fontWeight: FontWeight.w400, letterSpacing: 0.2),
                      ),
                    ),
                    const SizedBox(height: 10),
                     box(),
                  ]
                )
             )
            )
          )
        ]
      )
    );
  }
}