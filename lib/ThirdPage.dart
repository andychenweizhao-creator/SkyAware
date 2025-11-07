import 'package:flutter/material.dart';
import 'FirstPage.dart';
import 'FourthPage.dart';
import 'SecondPage.dart';
import 'FourthPage.dart';
class ThirdPage extends StatefulWidget {
  const ThirdPage({super.key});

  @override
  State<ThirdPage> createState() => _ThirdPageState();
}

class _ThirdPageState extends State<ThirdPage> {
  int currentIndex = 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF013A63),
              Color(0xFF014F86),
              Color(0xFF0353A4),
            ],
          ),
        ),
        child: Stack(
        children: [
          Positioned(
            top: 55,
            left: 26,
            child: Container(
              padding: EdgeInsets.all(8),
              child: Text(
                "Weather Detail",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Positioned(
            top: 120,
            left: 40,
            child: Text(
              "Real-Time & Forecast",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w400,
                color: Colors.white70,
                letterSpacing: 0.5
              ),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 45,
            child: Column(
              children: [
                FloatingActionButton(
                  backgroundColor: currentIndex == 0 ? Color(0XFF6F97D8) : Colors.white,
                  onPressed: () {
                    setState(() {
                      currentIndex = 0;
                    });
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => MyHomePage(title: 'Flutter Demo Home Page')),
                    );
                  },
                  child: Icon(
                    Icons.house,
                    color: currentIndex == 0 ? Colors.white : Colors.blue,
                  ),
                ),
                SizedBox(height: 6),
                Text("Home", style: TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
          Positioned(
            bottom: 20,
            left: 133,
            child: Column(
              children: [
                FloatingActionButton(
                  backgroundColor: currentIndex == 1 ? Color(0XFF6F97D8) : Colors.white,
                  onPressed: () {
                    setState(() {
                      currentIndex=1;
                    });
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => SecondPage()),
                    );
                  },
                  child: Icon(Icons.dashboard, color: Colors.blue),
                ),
                SizedBox(height: 6),
                Text(
                  "Dashboard",
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 20,
            left: 240,
            child: Column(
              children: [
                FloatingActionButton(
                  backgroundColor: currentIndex == 2 ? Color(0XFF6F97D8) : Colors.white,
                  onPressed: () {
                    setState(() {
                      currentIndex = 2;
                    });
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => ThirdPage()),
                    );
                  },
                  child: Icon(
                    Icons.cloud,
                    color: currentIndex == 2 ? Colors.white : Colors.blue,
                  ),
                ),
                SizedBox(height: 6),
                Text("Weather", style: TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
          Positioned(
            bottom: 20,
            left: 337,
            child: Column(
              children: [
                FloatingActionButton(
                  backgroundColor: currentIndex == 3 ? Color(0XFF6F97D8) : Colors.white,
                  onPressed: () {
                    setState(() {
                      currentIndex = 3;
                    });
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => FourthPage()),
                    );
                  },
                  child: Icon(
                    Icons.settings,
                    color: currentIndex == 3 ? Colors.white : Colors.blue,
                  ),
                ),
                SizedBox(height: 6),
                Text("Setting", style: TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}