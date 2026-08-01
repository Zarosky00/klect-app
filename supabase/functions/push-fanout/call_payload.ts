export const CALL_PAYLOAD_VERSION = "1";

export type CallPushRecord = {
  id: string;
  conversation_id: string;
  created_by: string;
  kind: "audio" | "video";
  status: string;
  expires_at: string;
};

export function buildCallPushData(
  notificationId: string,
  call: CallPushRecord,
  actorName: string,
  actorAvatarPath = "",
): Record<string, string> {
  if (call.status !== "ringing") {
    throw new Error("call-not-ringing");
  }
  return {
    payload_version: CALL_PAYLOAD_VERSION,
    notification_id: notificationId,
    type: "call",
    call_id: call.id,
    conversation_id: call.conversation_id,
    caller_id: call.created_by,
    caller_name: actorName,
    caller_avatar_path: actorAvatarPath,
    kind: call.kind,
    expires_at: call.expires_at,
    link: `klect://call/${call.id}`,
  };
}
