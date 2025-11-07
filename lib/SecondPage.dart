import 'package:flutter/material.dart';
import 'FirstPage.dart';
import 'ThirdPage.dart';
import 'FourthPage.dart';

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
      floatingActionButton: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            bottom: -20,
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
            bottom: -20,
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
            bottom:-20 ,
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
            bottom: -20,
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