import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class DepartureTimeBox extends StatefulWidget {
  @override
  _DepartureTimeBoxState createState() => _DepartureTimeBoxState();
}

class _DepartureTimeBoxState extends State<DepartureTimeBox> {
  TimeOfDay _departureTime = TimeOfDay.now();
  Duration _duration = Duration(minutes: 45);

  Future<void> _editTime() async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: _departureTime,
    );

    if (pickedTime != null && pickedTime != _departureTime) {
      setState(() {
        _departureTime = pickedTime;
      });
    }

    showModalBottomSheet(
      context: context,
      builder: (BuildContext builder) {
        return Container(
          height: MediaQuery.of(context).copyWith().size.height / 3,
          child: CupertinoTimerPicker(
            initialTimerDuration: _duration,
            minuteInterval: 5,
            onTimerDurationChanged: (Duration newDuration) {
              setState(() {
                _duration = newDuration;
              });
            },
          ),
        );
      },
    );
  }

  // Helper to calculate and format arrival time
  String _getArrivalTime(BuildContext context) {
    final now = DateTime.now();
    final departureDateTime = DateTime(now.year, now.month, now.day, _departureTime.hour, _departureTime.minute);
    final arrivalDateTime = departureDateTime.add(_duration);
    final arrivalTime = TimeOfDay.fromDateTime(arrivalDateTime);
    return arrivalTime.format(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF2C3E50),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Departure Time",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: _editTime,
                child: Text(
                  "Edit",
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTimeColumn("Time", _departureTime.format(context)),
              _buildTimeColumn("Duration", "${_duration.inMinutes} min"),
              _buildTimeColumn("Arriving", _getArrivalTime(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 24, // Adjusted for space
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
