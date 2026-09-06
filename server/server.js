import "dotenv/config";
import cors from "cors";
import express from "express";

const app = express();
const port = Number(process.env.PORT ?? 3000);
const host = process.env.HOST ?? "127.0.0.1";
const model = process.env.OLLAMA_MODEL ?? "qwen3:4b";
const ollamaURL = process.env.OLLAMA_URL ?? "http://127.0.0.1:11434";

app.use(cors());
app.use(express.json({ limit: "16kb" }));

app.get("/health", (_req, res) => {
  res.json({ ok: true, provider: "ollama", model });
});

app.post("/generate-meaning", async (req, res) => {
  const term = typeof req.body?.term === "string" ? req.body.term.trim() : "";

  if (!term) {
    return res.status(400).json({ error: "termを入力してください。" });
  }

  if (term.length > 120) {
    return res.status(400).json({ error: "termは120文字以内にしてください。" });
  }

  try {
    const response = await fetch(new URL("/api/chat", ollamaURL), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      signal: AbortSignal.timeout(90000),
      body: JSON.stringify({
      model,
      stream: false,
      think: false,
      format: { type: "object", properties: { meaning: { type: "string" } }, required: ["meaning"] },
      messages: [{ role: "system", content: `
あなたは単語カードアプリの裏面を作る学習補助AIです。
入力された表面の内容について、日本語で短く正確な意味だけを返してください。
英単語、熟語、漢字、歴史用語、理科用語、資格用語など幅広い学習語句に対応してください。
前置き、箇条書き、余計な説明は不要です。思考過程は出力しません。
出力はJSONのみです。例: {"meaning":"りんご。バラ科の木になる果物。"}
      `.trim() }, { role: "user", content: `「${term}」の単語カード裏面に書く意味を日本語で1文から2文で生成してください。 /no_think` }],
      options: { temperature: 0.2, num_predict: 200, num_ctx: 2048 },
      }),
    });

    if (!response.ok) {
      const message = response.status === 404
        ? `AIモデルが見つかりません。ターミナルで ollama pull ${model} を実行してください。`
        : "Ollamaで生成に失敗しました。Ollamaの状態を確認してください。";
      return res.status(502).json({ error: message });
    }
    const result = await response.json();
    let meaning = "";
    try {
      const content = JSON.parse(result.message?.content ?? "{}");
      if (typeof content.meaning === "string") meaning = content.meaning.trim();
    } catch { /* 不完全なJSONは生成失敗として扱う */ }
    if (!meaning) {
      return res.status(502).json({ error: "AIから意味が返りませんでした。もう一度生成してください。" });
    }

    res.json({ meaning });
  } catch (error) {
    console.error("Ollama request failed:", error.name);
    const message = error.name === "TimeoutError"
      ? "生成が時間切れになりました。ほかのアプリを閉じて、もう一度試してください。"
      : "Ollamaに接続できません。MacでOllamaを起動してください。";
    res.status(502).json({ error: message });
  }
});

app.listen(port, host, () => {
  console.log(`Meaning server listening on http://${host}:${port}`);
});
