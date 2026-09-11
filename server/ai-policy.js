export const normalizeAnswer = value => value.normalize("NFKC").trim().replace(/\s+/gu, " ").toLowerCase();

export function answersMatch(answer, expected) {
  const normalized = normalizeAnswer(answer);
  return normalized.length > 0 && normalized === normalizeAnswer(expected);
}

// 正解をAIに書き直させず、異なる誤答だけを採用する。
export async function generateQuestion(ask, data) {
  const distractors = [];
  const seen = new Set([normalizeAnswer(data.expected)]);
  let question = "";
  const stringField = { type: "string", minLength: 1 };
  const signal = AbortSignal.timeout(80000);
  for (let attempt = 0; attempt < 2; attempt++) {
    const result = await ask(
      "promptについて登録済みの答えexpectedが正解になる4択問題を作成します。questionに問題文、distractorsに明確に不正解の選択肢を3つ返してください。3つは互いに異なる内容にし、正解の同義語・言い換え・excludedにある選択肢を含めないでください。問題文に答えを書かないでください。",
      { ...data, excluded: [data.expected, ...distractors] },
      { question: stringField, distractors: { type: "array", items: stringField, minItems: 3, maxItems: 3 } },
      signal
    );
    if (typeof result?.question === "string" && result.question.trim()) question = result.question.trim();
    for (const value of Array.isArray(result?.distractors) ? result.distractors : []) {
      if (typeof value !== "string") continue;
      const key = normalizeAnswer(value);
      if (!key || seen.has(key)) continue;
      seen.add(key);
      distractors.push(value.trim());
    }
    if (question && distractors.length >= 3) {
      return { question, choices: [data.expected, ...distractors.slice(0, 3)] };
    }
  }
  throw new Error("AIが異なる4つの選択肢を作れませんでした。再試行するか、AIをオフにしてください。");
}
