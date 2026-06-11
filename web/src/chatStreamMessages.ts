export interface ChatMessage {
  id: string;
  role: "user" | "assistant";
  text: string;
  streaming?: boolean;
}

export function appendAssistantDelta(
  messages: ChatMessage[],
  assistantId: string,
  delta: string
): ChatMessage[] {
  let found = false;
  const next = messages.map((message) => {
    if (message.id !== assistantId) {
      return message;
    }
    found = true;
    return {
      ...message,
      text: message.text + delta,
      streaming: true,
    };
  });

  if (found) {
    return next;
  }

  return [
    ...messages,
    { id: assistantId, role: "assistant", text: delta, streaming: true },
  ];
}

export function finalizeAssistantMessage(
  messages: ChatMessage[],
  assistantId: string,
  text?: string
): ChatMessage[] {
  const finalText = text && text.length > 0 ? text : undefined;
  let found = false;
  const next = messages.map((message) => {
    if (message.id !== assistantId) {
      return message;
    }
    found = true;
    return {
      ...message,
      text: finalText ?? message.text,
      streaming: false,
    };
  });

  if (found) {
    return next;
  }

  if (!finalText) {
    return messages;
  }

  return [
    ...messages,
    { id: assistantId, role: "assistant", text: finalText, streaming: false },
  ];
}
