import test from "node:test";
import assert from "node:assert/strict";
import { answersMatch, generateQuestion } from "./ai-policy.js";

test("表記ゆれは一致し、意味や符号の違いは一致しない", () => {
  for (const [answer, expected] of [["apple fruit", "Apple fruit"], [" ＡＰＰＬＥ\u3000 fruit ", "apple  fruit"], ["apple\nfruit", " apple fruit "]]) {
    assert.equal(answersMatch(answer, expected), true);
  }
  for (const [answer, expected] of [["", " "], ["fruit", "apple fruit"], ["-1", "1"], ["cafe", "café"]]) {
    assert.equal(answersMatch(answer, expected), false);
  }
});

test("1枚のカードから正解を保持して4択を作成", async () => {
  let calls = 0;
  const result = await generateQuestion(async () => {
    calls++;
    return { question: "意味は？", distractors: ["本", "車", "猫"] };
  }, { prompt: "apple", expected: "りんご" });
  assert.equal(calls, 1);
  assert.deepEqual(result.choices, ["りんご", "本", "車", "猫"]);
});

test("重複した選択肢は除外し、不足分を再生成", async () => {
  let calls = 0;
  let firstSignal;
  const result = await generateQuestion(async (_instruction, data, _schema, signal) => {
    calls++;
    if (calls === 1) {
      firstSignal = signal;
      return { question: "意味は？", distractors: ["APPLE", " book ", "ＢＯＯＫ"] };
    }
    assert.equal(signal, firstSignal);
    assert.deepEqual(data.excluded, ["apple", "book"]);
    return { question: "意味は？", distractors: ["book", "car", "cat"] };
  }, { prompt: "りんご", expected: "apple" });
  assert.equal(calls, 2);
  assert.deepEqual(result.choices, ["apple", "book", "car", "cat"]);
});

test("再生成も失敗したら不完全な問題を返さず終了", async () => {
  let calls = 0;
  await assert.rejects(generateQuestion(async () => {
    calls++;
    return { question: "意味は？", distractors: ["apple", null, " "] };
  }, { prompt: "りんご", expected: "apple" }), /再試行/);
  assert.equal(calls, 2);
});
