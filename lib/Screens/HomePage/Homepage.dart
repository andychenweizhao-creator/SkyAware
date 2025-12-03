import 'package:flutter/material.dart';
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
            margin: const EdgeInsets.only(top: 40, left: 10),
            child: Expanded(
              child: SingleChildScrollView(
                child:Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                        children: [
                          Column(
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
                          Container(
                            margin: EdgeInsets.only(top: 24),
                            child: Icon(
                              Icons.flight,
                              color: Colors.white,
                              size: 60,
                            ),
                          )
                        ]
                      ),
                    const SizedBox(height: 10),
                    const Text(
                      "Flight Safety Index",
                      style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                    ),
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