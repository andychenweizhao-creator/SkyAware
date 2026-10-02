import os

file_path = "/Users/andy/StudioProjects/SkyAware/skyaware/lib/Screens/DashBoard/InFlightView.dart"
with open(file_path, "r") as f:
    content = f.read()

# add import
if "import 'package:cloud_functions/cloud_functions.dart';" not in content:
    content = content.replace("import 'package:google_generative_ai/google_generative_ai.dart';", 
    "import 'package:google_generative_ai/google_generative_ai.dart';\nimport 'package:cloud_functions/cloud_functions.dart';")

# replace method
old_method = """  Future<String> _getAiSummary(List<WeatherFeature> features) async {
    if (_model == null) {
      return "AI model not initialized. Please add your Gemini API key.";
    }

    final rawData = features.map((f) => f.rawProperties).toList();
    final jsonData = jsonEncode(rawData);

    final prompt = \"\"\"
    You are a flight safety Co-Pilot. The user tapped a location with these weather hazards: $jsonData. Analyze the Severity, Cloud Tops/Bases, and give a tactical recommendation. Be concise.
    \"\"\";

    final content = [Content.text(prompt)];
    final response = await _model!.generateContent(content);
    return response.text ?? "Could not generate a summary.";
  }"""

new_method = """  Future<String> _getAiSummary(List<WeatherFeature> features) async {
    final rawData = features.map((f) => f.rawProperties).toList();
    final jsonData = jsonEncode(rawData);

    final prompt = \"\"\"
    You are a flight safety Co-Pilot. The user tapped a location with these weather hazards: $jsonData. Analyze the Severity, Cloud Tops/Bases, and give a tactical recommendation. Be concise.
    \"\"\";

    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('askGemini');
      final result = await callable.call(<String, dynamic>{
        'prompt': prompt,
      });
      return (result.data['result'] ?? result.data['response']) as String;
    } on FirebaseFunctionsException catch (e) {
      print('Cloud Function Error: ${e.code} - ${e.message}');
      return "Co-Pilot Error: ${e.message}";
    } catch (e) {
      print('Unknown Error: $e');
      return "Could not reach the Co-Pilot. Please check your connection.";
    }
  }"""

content = content.replace(old_method, new_method)

with open(file_path, "w") as f:
    f.write(content)
