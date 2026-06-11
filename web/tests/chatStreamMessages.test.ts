import assert from "node:assert/strict";
import {
  appendAssistantDelta,
  finalizeAssistantMessage,
  type ChatMessage,
} from "../src/chatStreamMessages.js";

const userMessage: ChatMessage = {
  id: "user-1",
  role: "user",
  text: "What changed?",
};

{
  const messages = finalizeAssistantMessage(
    [userMessage],
    "assistant-1",
    "Final answer"
  );

  assert.deepEqual(messages, [
    userMessage,
    {
      id: "assistant-1",
      role: "assistant",
      text: "Final answer",
      streaming: false,
    },
  ]);
}

{
  const messages = appendAssistantDelta([userMessage], "assistant-1", "Hel");
  const updated = appendAssistantDelta(messages, "assistant-1", "lo");
  const finalized = finalizeAssistantMessage(
    updated,
    "assistant-1",
    "Hello"
  );

  assert.deepEqual(finalized, [
    userMessage,
    {
      id: "assistant-1",
      role: "assistant",
      text: "Hello",
      streaming: false,
    },
  ]);
}

{
  const messages = finalizeAssistantMessage([userMessage], "assistant-1");

  assert.deepEqual(messages, [userMessage]);
}
