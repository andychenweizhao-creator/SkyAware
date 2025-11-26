import 'package:flutter/material.dart';
import '../Screens/HomePage/Homepage.dart';
import '../Screens/DashBoard/DashBoard.dart';
import '../Screens/Weather/Weather.dart';
import '../Screens/Settings/Settings.dart';

class Navigationbar extends StatefulWidget{
  @override
  State<StatefulWidget> createState() {
    return NavigationbarState();
  }
}

class NavigationbarState extends State<Navigationbar>{
  int currentIndex = 0;

  final List<Widget> _pages = [

    HomePage(),
    DashBoard(),
    Weather(),
    Settings(),
  ];

  void onTabTapped(int index) {
    setState(() {
      currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: _pages,
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
                onTap: () => onTabTapped(0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        Icons.house,
                        color: currentIndex == 0 ? Colors.white : Colors.white70
                    ),
                    Text("Home",
                        style: TextStyle(
                            color: currentIndex == 0 ? Colors.white : Colors
                                .white70, fontSize: 12
                        )
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => onTabTapped(1),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        Icons.dashboard,
                        color: currentIndex == 1 ? Colors.white : Colors.white70
                    ),
                    Text("Dashboard",
                        style: TextStyle(
                            color: currentIndex == 1 ? Colors.white : Colors
                                .white70, fontSize: 12
                        )
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => onTabTapped(2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        Icons.cloud,
                        color: currentIndex == 2 ? Colors.white : Colors.white70
                    ),
                    Text("Weather",
                        style: TextStyle(
                            color: currentIndex == 2 ? Colors.white : Colors
                                .white70, fontSize: 12
                        )
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => onTabTapped(3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        Icons.settings,
                        color: currentIndex == 3 ? Colors.white : Colors.white70
                    ),
                    Text("Settings",
                        style: TextStyle(
                            color: currentIndex == 3 ? Colors.white : Colors
                                .white70, fontSize: 12
                        )
                    ),
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
