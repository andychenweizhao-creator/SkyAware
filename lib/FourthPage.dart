import 'package:flutter/material.dart';
import 'SecondPage.dart';
import 'ThirdPage.dart';
import 'FirstPage.dart';
class FourthPage extends StatefulWidget {
  const FourthPage({super.key});

  @override
  State<FourthPage> createState() => _FourthPageState();
}

class _FourthPageState extends State<FourthPage> {
  int currentIndex = 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0E1420),
      body: Stack(
        children: [

          Positioned(
            top: 80,
            left: 32,
            child: Text(
              "setting",
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: Colors.white
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Container(
          height: 70,
          margin: EdgeInsets.symmetric(horizontal: 40),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white30, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() => currentIndex = 0);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => MyHomePage(title: 'Flutter Demo Home Page')),
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.house, color: currentIndex == 0 ? Colors.white : Colors.white70),
                    Text("Home", style: TextStyle(
                        color: currentIndex == 0 ? Colors.white : Colors.white70, fontSize: 12
                    )),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => currentIndex = 1);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => SecondPage()),
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.dashboard, color: currentIndex == 1 ? Colors.white : Colors.white70),
                    Text("Dashboard", style: TextStyle(
                        color: currentIndex == 1 ? Colors.white : Colors.white70, fontSize: 12
                    )),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => currentIndex = 2);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => ThirdPage()),
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud, color: currentIndex == 2 ? Colors.white : Colors.white70),
                    Text("Weather", style: TextStyle(
                        color: currentIndex == 2 ? Colors.white : Colors.white70, fontSize: 12
                    )),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => currentIndex = 3);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => FourthPage()),
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.settings, color: currentIndex == 3 ? Colors.white : Colors.white70),
                    Text("Settings", style: TextStyle(
                        color: currentIndex == 3 ? Colors.white : Colors.white70, fontSize: 12
                    )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}