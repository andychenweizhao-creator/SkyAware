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
          Positioned(
            bottom: 30,
            left: 130,
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
            bottom: 30,
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
                Text(
                  "Weather",
                  style: TextStyle(color: Colors.white, fontSize: 14),
                )
              ],
            ),
          ),
          Positioned(
            bottom:30 ,
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
                Text(
                  "Setting",
                  style: TextStyle(color: Colors.white, fontSize: 14),
                )
              ],
            ),
          ),
          Positioned(
            bottom: 30,
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
                      MaterialPageRoute(
                        builder: (context) => MyHomePage(title: 'Flutter Demo Home Page'),
                      ),
                    );
                  },
                  child: Icon(
                    Icons.house,
                    color: currentIndex == 0 ? Colors.white : Colors.blue,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  "Home",
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}