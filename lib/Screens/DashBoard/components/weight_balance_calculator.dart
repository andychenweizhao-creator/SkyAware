import 'package:flutter/material.dart';

class WeightBalanceCalculator extends StatefulWidget {
  const WeightBalanceCalculator({super.key});

  @override
  State<WeightBalanceCalculator> createState() => _WeightBalanceCalculatorState();
}

class _WeightBalanceCalculatorState extends State<WeightBalanceCalculator> {
  final _formKey = GlobalKey<FormState>();
  
  // Weights in lbs
  double _pilotWeight = 170;
  double _passengerWeight = 0;
  double _fuelWeight = 0; // 6 lbs/gallon
  double _cargoWeight = 0;
  
  // Arms in inches (Dummy data for a C172-like aircraft)
  final double _pilotArm = 37.0;
  final double _passengerArm = 73.0;
  final double _fuelArm = 48.0;
  final double _cargoArm = 95.0;
  
  // Basic Empty Weight
  final double _emptyWeight = 1600;
  final double _emptyMoment = 60000; // approximated
  
  // Limits
  final double _maxGrossWeight = 2550;
  final double _cgForwardLimit = 35.0;
  final double _cgAftLimit = 47.3;

  double get _totalWeight => _emptyWeight + _pilotWeight + _passengerWeight + _fuelWeight + _cargoWeight;
  
  double get _totalMoment => 
      _emptyMoment + 
      (_pilotWeight * _pilotArm) + 
      (_passengerWeight * _passengerArm) + 
      (_fuelWeight * _fuelArm) + 
      (_cargoWeight * _cargoArm);
      
  double get _cg => _totalWeight > 0 ? _totalMoment / _totalWeight : 0;
  
  bool get _isWeightSafe => _totalWeight <= _maxGrossWeight;
  bool get _isCgSafe => _cg >= _cgForwardLimit && _cg <= _cgAftLimit;
  bool get _isSafe => _isWeightSafe && _isCgSafe;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A2F),
      appBar: AppBar(
        title: const Text("Weight & Balance", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCard(),
            const SizedBox(height: 24),
            const Text(
              "Load Inputs",
              style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildSlider("Pilot & Front Pax", _pilotWeight, 0, 500, (v) => setState(() => _pilotWeight = v)),
            _buildSlider("Rear Pax", _passengerWeight, 0, 500, (v) => setState(() => _passengerWeight = v)),
            _buildSlider("Fuel (lbs)", _fuelWeight, 0, 400, (v) => setState(() => _fuelWeight = v)),
            _buildSlider("Baggage / Cargo", _cargoWeight, 0, 200, (v) => setState(() => _cargoWeight = v)),
            
            const SizedBox(height: 24),
            _buildEnvelopeChart(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _isSafe ? Colors.green.withOpacity(0.5) : Colors.redAccent.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStat("Total Weight", "${_totalWeight.toStringAsFixed(1)} lbs", _isWeightSafe),
              _buildStat("CG", "${_cg.toStringAsFixed(1)} in", _isCgSafe),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: _isSafe ? Colors.green.withOpacity(0.2) : Colors.redAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isSafe ? Icons.check_circle : Icons.warning,
                  color: _isSafe ? Colors.green : Colors.redAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _isSafe ? "Within Envelope" : "Out of Limits",
                  style: TextStyle(
                    color: _isSafe ? Colors.green : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStat(String label, String value, bool isSafe) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: isSafe ? Colors.white : Colors.redAccent,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
  
  Widget _buildSlider(String label, double value, double min, double max, Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            Text("${value.toStringAsFixed(0)} lbs", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF0A84FF),
            inactiveTrackColor: Colors.white10,
            thumbColor: Colors.white,
            overlayColor: const Color(0xFF0A84FF).withOpacity(0.2),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
  
  Widget _buildEnvelopeChart() {
    return Container(
      height: 250,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: CustomPaint(
        painter: EnvelopePainter(
          cg: _cg,
          weight: _totalWeight,
          forwardLimit: _cgForwardLimit,
          aftLimit: _cgAftLimit,
          maxWeight: _maxGrossWeight,
          minWeight: _emptyWeight,
        ),
      ),
    );
  }
}

class EnvelopePainter extends CustomPainter {
  final double cg;
  final double weight;
  final double forwardLimit;
  final double aftLimit;
  final double maxWeight;
  final double minWeight;

  EnvelopePainter({
    required this.cg,
    required this.weight,
    required this.forwardLimit,
    required this.aftLimit,
    required this.maxWeight,
    required this.minWeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
      
    final fillPaint = Paint()
      ..color = Colors.blue.withOpacity(0.1)
      ..style = PaintingStyle.fill;
      
    final dotPaint = Paint()
      ..color = (cg >= forwardLimit && cg <= aftLimit && weight <= maxWeight) 
          ? Colors.green 
          : Colors.redAccent
      ..style = PaintingStyle.fill;

    // Define envelope box
    // X axis: CG (from forwardLimit - 2 to aftLimit + 2)
    // Y axis: Weight (from minWeight to maxWeight + 200)
    
    final xMin = forwardLimit - 5;
    final xMax = aftLimit + 5;
    final yMin = minWeight - 100;
    final yMax = maxWeight + 200;
    
    double normalizeX(double val) => (val - xMin) / (xMax - xMin) * size.width;
    double normalizeY(double val) => size.height - (val - yMin) / (yMax - yMin) * size.height;
    
    // Draw Axis
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), paint); // X
    canvas.drawLine(Offset(0, 0), Offset(0, size.height), paint); // Y
    
    // Draw Envelope
    final path = Path();
    path.moveTo(normalizeX(forwardLimit), normalizeY(minWeight));
    path.lineTo(normalizeX(forwardLimit), normalizeY(maxWeight)); // Simplified rectangle envelope
    path.lineTo(normalizeX(aftLimit), normalizeY(maxWeight));
    path.lineTo(normalizeX(aftLimit), normalizeY(minWeight));
    path.close();
    
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, paint..color = Colors.blue.withOpacity(0.5));
    
    // Draw Current Point
    final point = Offset(normalizeX(cg), normalizeY(weight));
    canvas.drawCircle(point, 6, dotPaint);
    
    // Labels
    final textStyle = const TextStyle(color: Colors.white54, fontSize: 10);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    
    textPainter.text = TextSpan(text: "${forwardLimit.toStringAsFixed(1)}", style: textStyle);
    textPainter.layout();
    textPainter.paint(canvas, Offset(normalizeX(forwardLimit) - 10, size.height - 15));
    
    textPainter.text = TextSpan(text: "${aftLimit.toStringAsFixed(1)}", style: textStyle);
    textPainter.layout();
    textPainter.paint(canvas, Offset(normalizeX(aftLimit) - 10, size.height - 15));
    
    textPainter.text = TextSpan(text: "${maxWeight.toStringAsFixed(0)} lbs", style: textStyle);
    textPainter.layout();
    textPainter.paint(canvas, Offset(5, normalizeY(maxWeight)));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
