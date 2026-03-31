const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { defineSecret } = require("firebase-functions/params");

const geminiApiKey = defineSecret("GEMINI_API_KEY");

exports.askGemini = onCall({ secrets: [geminiApiKey] }, async (request) => {
  try {
    const genAI = new GoogleGenerativeAI(geminiApiKey.value());
    // Using the fast flash model
    const model = genAI.getGenerativeModel({ model: "gemini-3-pro-preview" });

    // With onCall, Flutter data is automatically placed inside request.data
    const prompt = request.data.prompt;

    const result = await model.generateContent(prompt);
    const response = await result.response;
    const text = response.text();

    // With onCall, you just return the object! No res.send() needed.
    return { success: true, response: text };

  } catch (error) {
    console.error("Gemini Error:", error);
    // Securely pass the error back to Flutter
    throw new HttpsError("internal", error.message);
  }
});