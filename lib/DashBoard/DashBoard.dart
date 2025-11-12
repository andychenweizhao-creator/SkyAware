import 'package:flutter/material.dart';
import '../HomePage/HomePage.dart';
import '../Weather/Weather.dart';
import '../Settings/Settings.dart';
class SecondPage extends StatefulWidget {
  const SecondPage({super.key});

  @override
  State<SecondPage> createState() => _SecondPageState();
}

class _SecondPageState extends State<SecondPage> {
  int currentIndex = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0E1420),
      body: Container(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      margin: EdgeInsets.only(left:10,top: 50),
                      child:Text(
                        "Live Monitor",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 45,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                  ),
                ],
              ),
            )
          ],
        ),
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
                    MaterialPageRoute(builder: (context) => HomePage(title: 'Flutter Demo Home Page')),
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




