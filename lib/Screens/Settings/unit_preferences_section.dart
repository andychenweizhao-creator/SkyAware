import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/unit_settings_service.dart';

class UnitPreferencesSection extends StatelessWidget {
  final Color textColor;
  final Color secondaryTextColor;
  final Color containerColor;
  final Color borderColor;
  final bool isDark;
  final Function(String key, dynamic value) onUnitChange;


  const UnitPreferencesSection({
    super.key,
    required this.textColor,
    required this.secondaryTextColor,
    required this.containerColor,
    required this.borderColor,
    required this.isDark,
    required this.onUnitChange
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            "Unit Preferences",
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Consumer<UnitSettingsProvider>(
            builder: (context, units, child) {
              return Column(
                children: [
                  _buildUnitTile(
                    context: context,
                    icon: Icons.speed,
                    title: "Distance & Speed",
                    value: _getDistSpeedLabel(units.distanceSpeedUnit),
                    onTap: () => _showDistSpeedPicker(context, units),
                  ),
                  Divider(color: borderColor, height: 1, indent: 50),
                  _buildUnitTile(
                    context: context,
                    icon: Icons.height,
                    title: "Altitude",
                    value: _getAltitudeLabel(units.altitudeUnit),
                    onTap: () => _showAltitudePicker(context, units),
                  ),
                  Divider(color: borderColor, height: 1, indent: 50),
                  _buildUnitTile(
                    context: context,
                    icon: Icons.compress,
                    title: "Pressure",
                    value: _getPressureLabel(units.pressureUnit),
                    onTap: () => _showPressurePicker(context, units),
                  ),
                  Divider(color: borderColor, height: 1, indent: 50),
                  _buildUnitTile(
                    context: context,
                    icon: Icons.thermostat,
                    title: "Temperature",
                    value: _getTemperatureLabel(units.temperatureUnit),
                    onTap: () => _showTemperaturePicker(context, units),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUnitTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    final iconBgColor = isDark ? Colors.white.withValues(alpha: 0.05) : Colors
        .black.withValues(alpha: 0.05);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: textColor, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: textColor, fontSize: 16),
                ),
              ),
              Text(
                value,
                style: TextStyle(color: secondaryTextColor, fontSize: 14),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios,
                  color: textColor.withValues(alpha: 0.3), size: 14),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helpers for Display Text ---

  String _getDistSpeedLabel(DistanceSpeedUnit unit) {
    switch (unit) {
      case DistanceSpeedUnit.nauticalMilesKnots:
        return "NM & kt";
      case DistanceSpeedUnit.kilometersKph:
        return "km & km/h";
      case DistanceSpeedUnit.milesMph:
        return "mi & mph";
    }
  }

  String _getAltitudeLabel(AltitudeUnit unit) {
    switch (unit) {
      case AltitudeUnit.feet: return "Feet";
      case AltitudeUnit.meters: return "Meters";
    }
  }

  String _getPressureLabel(PressureUnit unit) {
    switch (unit) {
      case PressureUnit.inHg: return "inHg";
      case PressureUnit.hPa: return "hPa";
    }
  }

  String _getTemperatureLabel(TemperatureUnit unit) {
    switch (unit) {
      case TemperatureUnit.celsius: return "Celsius (°C)";
      case TemperatureUnit.fahrenheit: return "Fahrenheit (°F)";
    }
  }

  // --- Pickers ---

  void _showDistSpeedPicker(BuildContext context, UnitSettingsProvider provider) {
    _showPicker(
      context,
      "Distance & Speed",
      DistanceSpeedUnit.values,
      provider.distanceSpeedUnit,
      (unit) => _getDistSpeedLabel(unit),
      (unit) {
        provider.setDistanceSpeedUnit(unit);
        onUnitChange('distanceUnit', unit);
      },
    );
  }

  void _showAltitudePicker(BuildContext context, UnitSettingsProvider provider) {
    _showPicker(
      context,
      "Altitude",
      AltitudeUnit.values,
      provider.altitudeUnit,
      (unit) => _getAltitudeLabel(unit),
      (unit) {
        provider.setAltitudeUnit(unit);
        onUnitChange('altitudeUnit', unit);
      },
    );
  }

  void _showPressurePicker(BuildContext context, UnitSettingsProvider provider) {
    _showPicker(
      context,
      "Pressure",
      PressureUnit.values,
      provider.pressureUnit,
      (unit) => _getPressureLabel(unit),
      (unit) {
        provider.setPressureUnit(unit);
        onUnitChange('pressureUnit', unit);
      },
    );
  }

  void _showTemperaturePicker(BuildContext context, UnitSettingsProvider provider) {
    _showPicker(
      context,
      "Temperature",
      TemperatureUnit.values,
      provider.temperatureUnit,
      (unit) => _getTemperatureLabel(unit),
      (unit) {
        provider.setTemperatureUnit(unit);
        onUnitChange('temperatureUnit', unit);
      },
    );
  }

  void _showPicker<T>(
    BuildContext context,
    String title,
    List<T> options,
    T selectedValue,
    String Function(T) labelBuilder,
    Function(T) onSelected,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C2C54) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  "Select $title Unit",
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...options.map((option) {
                final isSelected = option == selectedValue;
                return ListTile(
                  title: Text(
                    labelBuilder(option),
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF0A84FF) : textColor,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF0A84FF)) : null,
                  onTap: () {
                    onSelected(option);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}
