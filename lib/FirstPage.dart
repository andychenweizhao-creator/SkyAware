import 'package:flutter/material.dart';
import 'SecondPage.dart';
import 'ThirdPage.dart';
import 'FourthPage.dart';
import 'Firstpage.dart';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int currentIndex = 0;
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context)
  {
    return Scaffold(
      backgroundColor: Color(0xFF0E1420),
      body: Container(
        margin: EdgeInsets.only(top: 40,left: 10),
        child: Row(
          children: [
            Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "SkyAware",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 60,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text
                      (
                        "Sky Safety Monitor",
                        style:TextStyle
                          (
                          color : Color(0xFFA7B3C4),
                          fontSize: 20
                        )
                    ),
                    Container(
                      margin: EdgeInsets.only(left:64,top: 50),
                      child: Text(
                        "Flight Safety Index",
                        style: TextStyle
                          (
                            color: Color(0xFFF9FAFA),
                            fontSize: 29
                        ),
                      ),
                    ),
                    Container
                      (
                      margin: EdgeInsets.only(left: 70,top: 3),
                      child:
                      Text(
                        "Real-Time Assessment",
                        style: TextStyle(
                          fontSize: 21,
                          color: Color(0xFFA8B3C2),
                        ),
                      ),
                    ),
                  ],
                ),
            ),
            Align(
              child: Padding(
                padding: EdgeInsets.only(right: 35,bottom: 780),
                child: Icon(
                  Icons.flight,
                  size: 60,
                  color: Colors.blue,
                ),
              ),
            ),
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
