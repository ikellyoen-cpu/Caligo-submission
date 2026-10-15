const express = require("express");
const cors = require("cors");
require("dotenv").config();

const { GoogleGenAI } = require("@google/genai");

const app = express();

app.use(cors());
app.use(express.json());

const ai = new GoogleGenAI({
  apiKey: process.env.GEMINI_API_KEY
});

app.get("/", (req, res) => {
  res.send("Caligo AI backend is running!");
});

app.post("/chat", async (req, res) => {
  try {
    const message = req.body.message;
    const userData = req.body.userData || {};

    if (!message) {
      return res.status(400).json({
        error: "No message provided"
      });
    }
	 const contextPrompt = `You are Caligo AI, a friendly assistant for someone with memory difficulties.
User info:
- Name: ${userData.name}
- Age: ${userData.age}
- Sleep per day: ${userData.sleep}
- Diet: ${userData.diet}
- Allergies: ${userData.allergies}
- Emergency contact: ${userData.emergency}

Respond warmly and helpfully to this message from the user: "${message}"`;

    console.log("User said:", message);

    const interaction = await ai.interactions.create({
      model: "gemini-3.8-flash",
      input: contextPrompt
    });

    const reply = interaction.output_text;

    console.log("Gemini replied:", reply);

    res.json({
      reply: reply
    });

  } catch (error) {
    console.error("Gemini error:", error);

    res.status(500).json({
      error: "Failed to get a response from Gemini"
    });
  }
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`Caligo backend running on port ${PORT}`);
});