import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';
import '../services/weather_service.dart';
import '../services/unit_settings_service.dart';
import 'AppAnimations.dart';

class AirportDetailSheet extends StatefulWidget {
  final String icao;
  late final HttpsCallable aiCallable;

  AirportDetailSheet({
    super.key,
    required this.icao,
  }) {
    aiCallable = FirebaseFunctions.instance.httpsCallable('askGemini');
  }

  @override
  State<AirportDetailSheet> createState() => _AirportDetailSheetState();
}

class _AirportDetailSheetState extends State<AirportDetailSheet> {
  bool _isLoading = true;
  String _errorMessage = '';
  Map<String, dynamic>? _metarData;
  Map<String, dynamic>? _aiAnalysis;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 1. Fetch METAR
      final metar = await WeatherService.fetchMetar(widget.icao);
      
      Map<String, dynamic>? analysis;
      // 2. Analyze with AI if model exists
      try {
        analysis = await WeatherService.analyzeSafety(metar, widget.aiCallable);
      } catch (e) {
        debugPrint("AI Analysis failed: $e");
        // Surface the actual error to the UI for debugging
        analysis = {"summary": "Co-Pilot Error: $e", "score": null};
      }

      if (mounted) {
        setState(() {
          _metarData = metar;
          _aiAnalysis = analysis;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Color _getScoreColor(int? score, bool isDark) {
    if (score == null) return Colors.grey;
    if (isDark) {
      if (score >= 90) return Colors.greenAccent;
      if (score >= 75) return Colors.lightGreenAccent;
      if (score >= 60) return Colors.yellowAccent;
      if (score >= 40) return Colors.orangeAccent;
      return Colors.redAccent;
    } else {
      if (score >= 90) return Colors.green;
      if (score >= 75) return Colors.lightGreen;
      if (score >= 60) return Colors.amber;
      if (score >= 40) return Colors.deepOrange;
      return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E).withOpacity(0.95) : Colors.white.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
      ),
      child: Column(
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.grey.withOpacity(0.5), borderRadius: BorderRadius.circular(2)),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.local_airport, size: 28, color: Colors.cyanAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.icao, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                      if (_metarData != null && _metarData!['site'] != null)
                        Text(_metarData!['site'], style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.7))),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadData,
                )
              ],
            ),
          ),
          const Divider(),

          // Content
          Expanded(
            child: _isLoading 
                ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
                : _errorMessage.isNotEmpty
                    ? Center(child: Text(_errorMessage, style: const TextStyle(color: Colors.red)))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            // Safety Gauge
                            if (_aiAnalysis != null)
                              _buildSafetyGauge(_aiAnalysis!['score'] as int?, theme, isDark),
                            
                            const SizedBox(height: 32),
                            
                            // Metrics Grid
                            _buildMetricsGrid(theme, isDark),
                            
                            const SizedBox(height: 24),
                            
                            // AI Insight
                            if (_aiAnalysis != null && _aiAnalysis!['summary'] != null)
                              _buildAiInsightCard(theme, _aiAnalysis!['summary']),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyGauge(int? score, ThemeData theme, bool isDark) {
    if (score == null) return const SizedBox.shrink();
    final color = _getScoreColor(score, isDark);
    
    return SpringButton(
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 160, height: 160,
            child: CircularProgressIndicator(
              value: 1.0, strokeWidth: 12, color: theme.colorScheme.onSurface.withOpacity(0.05), strokeCap: StrokeCap.round,
            ),
          ),
          SizedBox(
            width: 160, height: 160,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: score / 100.0),
              duration: const Duration(seconds: 2),
              curve: Curves.easeOutExpo,
              builder: (context, value, child) {
                return CircularProgressIndicator(
                  value: value, strokeWidth: 12, color: color, backgroundColor: Colors.transparent, strokeCap: StrokeCap.round,
                );
              },
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedCounter(
                value: score,
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface, height: 1.0),
              ),
              Text("SAFETY SCORE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color.withOpacity(0.9), letterSpacing: 1.0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(ThemeData theme, bool isDark) {
    if (_metarData == null) return const SizedBox.shrink();
    final units = Provider.of<UnitSettingsProvider>(context);

    // Simplified extraction logic mirroring HomePage
    final fltcat = _metarData!['fltcat']?.toString() ?? 'N/A';
    Color catColor = theme.colorScheme.onSurface;
    switch (fltcat) {
      case 'VFR': catColor = isDark ? Colors.greenAccent : Colors.green; break;
      case 'MVFR': catColor = Colors.blueAccent; break;
      case 'IFR': catColor = isDark ? Colors.redAccent : Colors.red; break;
      case 'LIFR': catColor = Colors.purpleAccent; break;
      default: catColor = Colors.grey;
    }

    final altimMb = _metarData!['altim'];
    String altimDisplay = "29.92 inHg";
    if (altimMb is num) {
      if (units.pressureUnit == PressureUnit.inHg) {
        altimDisplay = "${(altimMb * 0.02953).toStringAsFixed(2)} inHg";
      } else {
        altimDisplay = "${altimMb.round()} hPa";
      }
    }

    final temp = _metarData!['temp']?.toString() ?? '0';
    final dewp = _metarData!['dewp']?.toString() ?? '0';
    
    dynamic rawDir = _metarData!['wdir'];
    dynamic rawSpd = _metarData!['wspd'];
    String windDisplay = "${rawDir ?? 'VRB'}@${rawSpd ?? 0}kt";

    String skyCond = "SKC";
    if (_metarData!.containsKey('clouds')) {
      final List<dynamic> clouds = _metarData!['clouds'] ?? [];
      if (clouds.isNotEmpty) skyCond = "${clouds[0]['cover']} ${clouds[0]['base'] ?? ''}".trim();
    }
    
    String visDisplay = _metarData!['visib']?.toString() ?? '10+';
    final wx = _metarData!['wx']?.toString() ?? '';

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      children: [
        _buildMetricCard("FLIGHT CAT", fltcat, theme, isDark, icon: Icons.flight, color: catColor, isPill: true),
        _buildMetricCard("ALTIMETER", altimDisplay, theme, isDark, icon: Icons.speed),
        _buildMetricCard("TEMP / DEWP", "$temp° / $dewp°", theme, isDark, icon: Icons.thermostat),
        _buildMetricCard("WIND", windDisplay, theme, isDark, icon: Icons.air),
        _buildMetricCard("SKY COND", skyCond, theme, isDark, icon: Icons.cloud),
        _buildMetricCard("VIS / WX", "$visDisplay SM $wx", theme, isDark, icon: Icons.visibility),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, ThemeData theme, bool isDark, {
    IconData? icon, Color? color, bool isPill = false,
  }) {
    final contentColor = color ?? theme.colorScheme.onSurface;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold)),
                  if (icon != null) Icon(icon, color: theme.colorScheme.onSurface.withOpacity(0.4), size: 14),
                ],
              ),
              if (isPill)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: contentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: contentColor.withOpacity(0.5)),
                  ),
                  child: Text(value, style: TextStyle(color: contentColor, fontWeight: FontWeight.bold, fontSize: 16)),
                )
              else
                Text(value, style: TextStyle(color: contentColor, fontWeight: FontWeight.bold, fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiInsightCard(ThemeData theme, String text) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.purpleAccent.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 18),
                  const SizedBox(width: 8),
                  Text("Co-Pilot Insight", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                ],
              ),
              const SizedBox(height: 8),
              Text(text, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.8), height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}
