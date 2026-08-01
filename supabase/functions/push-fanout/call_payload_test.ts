import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { buildCallPushData } from "./call_payload.ts";

const ringing = {
  id: "call-1",
  conversation_id: "conversation-1",
  created_by: "caller-1",
  kind: "video" as const,
  status: "ringing",
  expires_at: "2026-08-01T12:00:45Z",
};

Deno.test("call payload is versioned, data-only ready and deep-linkable", () => {
  assertEquals(buildCallPushData("notification-1", ringing, "Akash", "a.jpg"), {
    payload_version: "1",
    notification_id: "notification-1",
    type: "call",
    call_id: "call-1",
    conversation_id: "conversation-1",
    caller_id: "caller-1",
    caller_name: "Akash",
    caller_avatar_path: "a.jpg",
    kind: "video",
    expires_at: "2026-08-01T12:00:45Z",
    link: "klect://call/call-1",
  });
});

Deno.test("stale calls cannot produce an incoming payload", () => {
  assertThrows(
    () =>
      buildCallPushData(
        "notification-1",
        { ...ringing, status: "missed" },
        "Akash",
      ),
    Error,
    "call-not-ringing",
  );
});
