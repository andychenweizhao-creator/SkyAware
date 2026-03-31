import os

file_path = '/Users/andy/StudioProjects/SkyAware/skyaware/lib/Screens/DashBoard/InFlightView.dart'
with open(file_path, 'r') as f:
    content = f.read()

# The exact snippet from the file
old_block = """      final aiResult = await AiEmergencyService.calculateEmergencyRoute(
        lat: _currentPosition!.latitude,
        lon: _currentPosition!.longitude,
        alt: _currentAltitudeFeet ?? 0,
        heading: _currentPosition!.heading,
        aircraftType: acType,
        emergencyType: emType,
        candidates: candidates,
        model: _model!,
      );"""

new_block = """      final aiResult = await AiEmergencyService.calculateEmergencyRoute(
        lat: _currentPosition!.latitude,
        lon: _currentPosition!.longitude,
        alt: _currentAltitudeFeet ?? 0,
        heading: _currentPosition!.heading,
        aircraftType: acType,
        emergencyType: emType,
        candidates: candidates,
      );"""

if old_block in content:
    content = content.replace(old_block, new_block)
    with open(file_path, 'w') as f:
        f.write(content)
    print("Replaced with exact matching!")
else:
    print("Exact block still not found...")