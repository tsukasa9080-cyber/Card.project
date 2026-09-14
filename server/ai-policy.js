export const normalizeAnswer = value => value.normalize("NFKC").trim().replace(/\s+/gu, " ").toLowerCase();

export function answersMatch(answer, expected) {
  const normalized = normalizeAnswer(answer);
  return normalized.length > 0 && normalized === normalizeAnswer(expected);
}

// 正解をAIに書き直させず、異なる誤答だけを採用する。
export async function generateQuestion(ask, data) {
  const distractors = [];
  const expectedKey = normalizeAnswer(data.expected);
  const seen = new Set([expectedKey]);
  let question = "";
  const stringField = { type: "string" };
  const signal = AbortSignal.timeout(80000);
  for (let attempt = 0; attempt < 2; attempt++) {
    let result;
    try {
      result = await ask(
        "単語promptの意味を問う4択問題を作成。expectedが正解です。questionに答えを含まない短い問題文、distractorsに明らかに間違った答えを3つ返す。正解と同義の語、同じ候補、excludedの候補は使わない。各候補は短い語句にする。",
        { ...data, excluded: distractors },
        { question: stringField, distractors: { type: "array", items: stringField } },
        signal
      );
    } catch (error) {
      if (attempt === 1 || signal.aborted) throw error;
      continue;
    }
    if (typeof result?.question === "string" && result.question.trim()) question = result.question.trim();
    for (const value of Array.isArray(result?.distractors) ? result.distractors : []) {
      if (typeof value !== "string") continue;
      const key = normalizeAnswer(value);
      if (!key || seen.has(key)) continue;
      // 長い正解の一部（例：「りんご。バラ科…」に対する「りんご」）も誤答にしない。
      if (expectedKey.includes(key) || key.includes(expectedKey)) continue;
      seen.add(key);
      distractors.push(value.trim());
    }
    if (question && distractors.length >= 3) {
      return { question, choices: [data.expected, ...distractors.slice(0, 3)] };
    }
  }
  throw new Error("AIが異なる4つの選択肢を作れませんでした。再試行するか、AIをオフにしてください。");
}
