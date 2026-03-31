import os

file_path = '/Users/andy/StudioProjects/SkyAware/skyaware/lib/Screens/DashBoard/InFlightView.dart'
with open(file_path, 'r') as f:
    content = f.read()

lines = content.split('\n')
new_lines = []
skip = False
for line in lines:
    if "final aiResult = await AiEmergencyService.calculateEmergencyRoute(" in line:
        new_lines.append(line)
        new_lines.append("        lat: _currentPosition!.latitude,")
        new_lines.append("        lon: _currentPosition!.longitude,")
        new_lines.append("        alt: _currentAltitudeFeet ?? 0,")
        new_lines.append("        heading: _currentPosition!.heading,")
        new_lines.append("        aircraftType: acType,")
        new_lines.append("        emergencyType: emType,")
        new_lines.append("        candidates: candidates,")
        new_lines.append("      );")
        skip = True
    elif skip:
        if ");" in line:
            skip = False
    else:
        new_lines.append(line)

content = '\n'.join(new_lines)

with open(file_path, 'w') as f:
    f.write(content)
print("Replaced!")